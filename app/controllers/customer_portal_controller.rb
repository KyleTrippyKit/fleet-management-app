# app/controllers/customer_portal_controller.rb
class CustomerPortalController < ApplicationController
  layout 'customer_portal'
  
  skip_before_action :authenticate_user!
  skip_before_action :verify_authenticity_token, only: [:authenticate]
  before_action :authenticate_customer, only: [:dashboard, :quotation, :approve, :status, :logout]
  before_action :set_customer_reception, only: [:dashboard, :status]
  before_action :set_quotation, only: [:quotation, :approve]
  before_action :authorize_quotation_access, only: [:quotation, :approve]
  
  # Helper methods
  helper_method :status_badge_color, :work_progress_percentage, :current_customer_reception

  # VMCOTT Contact Information
  VMCOTT_PHONE = "868-625-1234"
  VMCOTT_EMAIL = "service@vmcott.com"
  VMCOTT_ADDRESS = "Golden Grove Road, Piarco, Trinidad"

  def login
    if session[:customer_token].present? && current_customer_reception.present?
      redirect_to customer_dashboard_path and return
    end
  end

  def authenticate
    vehicle = Vehicle.find_by(license_plate: params[:license_plate])
    reception = ReceptionLog.find_by(
      vehicle_id: vehicle&.id,
      receipt_number: params[:receipt_number]
    )
    
    if reception
      token = SecureRandom.hex(32)
      reception.update(
        portal_access_token: token,
        portal_access_expires_at: 30.days.from_now,
        customer_email: params[:email],
        customer_phone: params[:phone],
        customer_name: params[:customer_name]
      )
      
      session[:customer_token] = token
      session[:customer_log_id] = reception.id
      
      redirect_to customer_dashboard_path, notice: "Welcome! You can track your vehicle repair here."
    else
      flash.now[:alert] = "Invalid license plate or receipt number. Please check and try again."
      render :login
    end
  end

  def recover
    # Show recovery form
  end

  def send_recovery
    @reception = ReceptionLog.find_by(customer_email: params[:email]) if params[:email].present?
    @reception ||= ReceptionLog.find_by(customer_phone: params[:phone]) if params[:phone].present?
    
    if @reception
      @reception.send_recovery_email!
      flash[:notice] = "Recovery email sent to #{@reception.customer_email}. Please check your inbox."
      redirect_to customer_login_path
    else
      flash[:alert] = "No records found with that email or phone number. Please contact VMCOTT for assistance."
      render :recover
    end
  end

  def contact_support
    @vmcott_phone = VMCOTT_PHONE
    @vmcott_email = VMCOTT_EMAIL
    @vmcott_address = VMCOTT_ADDRESS
  end

  def dashboard
    @reception = @customer_reception
    @vehicle = @reception&.vehicle
    @condition_report = @reception&.condition_report
    @inspection = Inspection.find_by(vehicle: @vehicle) if @vehicle
    @jobs = @inspection&.inspection_jobs || []
    @parts_requests = @inspection&.parts_requests || []
    @quotation = Quotation.find_by(vehicle: @vehicle) if @vehicle
    @inspection_progress = work_progress_percentage(@inspection)
    @vmcott_phone = VMCOTT_PHONE
  end

  def quotation
    @quotation = Quotation.find(params[:id])
    @inspection = Inspection.find_by(vehicle: @quotation.vehicle) if @quotation.vehicle
    @jobs = @quotation.quotation_jobs
    @parts = @quotation.quotation_job_parts
    @total_cost = @quotation.amount || @quotation.quotation_jobs.sum(&:total_labor_cost) + @quotation.quotation_job_parts.sum(&:total_price)
  end

  # 🔥 REVISED: Approve method with safe notification handling
  def approve
    # Make sure we have a valid quotation ID
    if params[:id].blank?
      flash[:alert] = "Quotation ID is missing."
      redirect_to customer_dashboard_path and return
    end
    
    @quotation = Quotation.find_by(id: params[:id])
    
    if @quotation.nil?
      flash[:alert] = "Quotation not found."
      redirect_to customer_dashboard_path and return
    end
    
    # Use inspection_id instead of .inspection association
    @inspection = Inspection.find_by(id: @quotation.inspection_id)
    
    if @inspection.nil?
      flash[:alert] = "Inspection not found for this quotation."
      redirect_to customer_dashboard_path and return
    end
    
    if params[:approve_all].present?
      # Approve all jobs
      @quotation.quotation_jobs.update_all(client_approved: true, client_approved_at: Time.current)
      # Use 'accepted' instead of 'approved' (valid Quotation status)
      @quotation.update(status: 'accepted', accepted_at: Time.current)
      
      # Update ALL jobs from 'pending_approval' to 'approved'
      updated_count = @inspection.inspection_jobs.update_all(status: 'approved')
      
      flash[:notice] = "All jobs approved. Work will begin shortly."
      Rails.logger.info "Customer approved all #{updated_count} jobs for inspection #{@inspection.id}"
      
    elsif params[:approved_jobs].present?
      # Approve selected jobs
      approved_ids = params[:approved_jobs]
      @quotation.quotation_jobs.where(id: approved_ids).update_all(client_approved: true, client_approved_at: Time.current)
      @quotation.quotation_jobs.where.not(id: approved_ids).update_all(client_approved: false)
      
      # Update only approved jobs to 'approved' status
      approved_job_ids = @quotation.quotation_jobs.where(id: approved_ids).pluck(:inspection_job_id).compact
      
      if approved_job_ids.any?
        updated_count = @inspection.inspection_jobs.where(id: approved_job_ids).update_all(status: 'approved')
        Rails.logger.info "Customer approved #{updated_count} specific jobs for inspection #{@inspection.id}"
      end
      
      if approved_ids.length == @quotation.quotation_jobs.count
        @quotation.update(status: 'accepted', accepted_at: Time.current)
        flash[:notice] = "All jobs approved. Work will begin shortly."
      else
        @quotation.update(status: 'partially_rejected')
        flash[:notice] = "#{approved_ids.length} job(s) approved. The remaining jobs will not be performed."
      end
    else
      flash[:alert] = "Please select at least one job to approve."
      redirect_to customer_quotation_path(@quotation) and return
    end
    
    # Update inspection status if all jobs are now approved
    if @inspection.inspection_jobs.where(status: 'approved').count > 0
      @inspection.update(status: 'approved') if @inspection.status == 'awaiting_approval'
    end
    
    # 🔥 SAFELY notify supervisor (wrap in begin/rescue)
    supervisor_ids = User.where(role: 'workshop_supervisor').pluck(:id)
    if supervisor_ids.any?
      begin
        Notification.create!(
          title: "Quotation Approved by Customer",
          message: "Customer has approved #{@quotation.quotation_jobs.where(client_approved: true).count} out of #{@quotation.quotation_jobs.count} jobs for vehicle #{@quotation.vehicle&.license_plate}",
          link: "/vmcott/workshop_supervisor/inspections/#{@inspection.id}",
          user_id: supervisor_ids,
          notifiable_type: 'Quotation',
          notifiable_id: @quotation.id,
          notification_type: 'success'
        )
        Rails.logger.info "Notified #{supervisor_ids.count} supervisors"
      rescue => e
        Rails.logger.error "Failed to create supervisor notification: #{e.message}"
      end
    else
      Rails.logger.warn "No workshop supervisors found to notify"
    end
    
    # 🔥 SAFELY notify mechanics (wrap in begin/rescue)
    approved_job_count = @inspection.inspection_jobs.where(status: 'approved').count
    if approved_job_count > 0
      mechanic_ids = User.where(role: 'mechanic').pluck(:id)
      if mechanic_ids.any?
        mechanic_ids.each do |mechanic_id|
          begin
            Notification.create!(
              user_id: mechanic_id,
              title: "New Work Available",
              message: "Customer approved work for #{@inspection.vehicle&.license_plate}. #{approved_job_count} job(s) ready.",
              link: vmcott_mechanic_dashboard_path,
              notification_type: 'success',
              notifiable: @inspection
            )
          rescue => e
            Rails.logger.error "Failed to create notification for mechanic #{mechanic_id}: #{e.message}"
          end
        end
        Rails.logger.info "Notified #{mechanic_ids.count} mechanics"
      else
        Rails.logger.warn "No mechanics found to notify"
      end
    end
    
    redirect_to customer_dashboard_path, notice: flash[:notice]
  end
  
  def status
    @reception = @customer_reception
    @inspection = Inspection.find_by(vehicle: @reception&.vehicle) if @reception&.vehicle
    @vehicle = @reception&.vehicle
    @jobs = @inspection&.inspection_jobs || []
    @parts_requests = @inspection&.parts_requests || []
    @timeline = build_timeline(@reception, @inspection)
  end

  def logout
    session[:customer_token] = nil
    session[:customer_log_id] = nil
    redirect_to customer_login_path, notice: "You have been logged out."
  end

  private

  def authenticate_customer
    token = session[:customer_token] || params[:token]
    
    if token.blank?
      redirect_to customer_login_path, alert: "Please log in to continue." and return false
    end
    
    @reception = ReceptionLog.find_by(portal_access_token: token)
    
    if @reception.nil?
      session[:customer_token] = nil
      redirect_to customer_login_path, alert: "Invalid session. Please log in again." and return false
    end
    
    if @reception.portal_access_expires_at.present? && @reception.portal_access_expires_at < Time.current
      session[:customer_token] = nil
      redirect_to customer_login_path, alert: "Your session has expired. Please log in again." and return false
    end
    
    if params[:token].present? && session[:customer_token].blank?
      session[:customer_token] = token
      session[:customer_log_id] = @reception.id
    end
    
    true
  end

  def set_customer_reception
    @customer_reception = current_customer_reception
    if @customer_reception.nil?
      redirect_to customer_login_path, alert: "Session expired. Please log in again."
    end
  end

  def set_quotation
    @quotation = Quotation.find_by(id: params[:id])
    if @quotation.nil?
      redirect_to customer_dashboard_path, alert: "Quotation not found."
      return false
    end
    true
  end

  def authorize_quotation_access
    return unless @quotation && @customer_reception
    
    unless @quotation.vehicle_id == @customer_reception.vehicle_id
      redirect_to customer_dashboard_path, alert: "Access denied. You can only view quotations for your vehicle."
    end
  end

  def current_customer_reception
    return nil unless session[:customer_token]
    @current_customer_reception ||= ReceptionLog.find_by(portal_access_token: session[:customer_token])
  end

  def build_timeline(reception, inspection)
    timeline = []
    
    timeline << {
      date: reception.received_at,
      title: "Vehicle Received",
      description: "Your vehicle was received at VMCOTT",
      icon: "bi-box-arrow-in-right",
      status: "completed"
    }
    
    if reception.condition_report&.completed?
      timeline << {
        date: reception.condition_report.signed_at || reception.created_at,
        title: "Condition Report Completed",
        description: "Initial condition assessment completed",
        icon: "bi-clipboard-check",
        status: "completed"
      }
    end
    
    if inspection.present?
      timeline << {
        date: inspection.created_at,
        title: "Inspection Started",
        description: "Technical inspection in progress",
        icon: "bi-search",
        status: inspection.status != 'pending_inspection' ? "completed" : "in_progress"
      }
      
      if inspection.inspection_jobs.any?
        completed_jobs = inspection.inspection_jobs.where.not(completed_at: nil).count
        total_jobs = inspection.inspection_jobs.count
        
        timeline << {
          date: inspection.inspection_jobs.where.not(completed_at: nil).first&.completed_at || Time.current,
          title: "Repair Work",
          description: "#{completed_jobs} of #{total_jobs} repair jobs completed",
          icon: "bi-tools",
          status: completed_jobs == total_jobs ? "completed" : "in_progress"
        }
      end
      
      if inspection.status == 'ready_for_pickup' || inspection.status == 'completed'
        timeline << {
          date: inspection.ready_for_pickup_at || inspection.updated_at,
          title: "Quality Control Passed",
          description: "Vehicle passed quality control inspection",
          icon: "bi-check-circle",
          status: "completed"
        }
      end
      
      if inspection.ready_for_pickup_at.present?
        timeline << {
          date: inspection.ready_for_pickup_at,
          title: "Ready for Pickup",
          description: "Your vehicle is ready for pickup",
          icon: "bi-truck",
          status: "completed"
        }
      end
    end
    
    timeline.sort_by { |t| t[:date] || Time.current }
  end

  def status_badge_color(status)
    case status.to_s
    when 'pending_inspection' then 'secondary'
    when 'approved_for_repair' then 'success'
    when 'in_progress' then 'warning'
    when 'parts_coordinator_review' then 'info'
    when 'ready_for_qc' then 'info'
    when 'qc_completed' then 'success'
    when 'ready_for_pickup' then 'success'
    when 'completed' then 'success'
    when 'approved' then 'success'
    when 'partially_approved' then 'warning'
    else 'primary'
    end
  end

  def work_progress_percentage(inspection)
    return 0 unless inspection.present?
    total_jobs = inspection.inspection_jobs.count
    return 0 if total_jobs == 0
    completed_jobs = inspection.inspection_jobs.where.not(completed_at: nil).count
    ((completed_jobs.to_f / total_jobs) * 100).round
  end
end