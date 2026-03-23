# app/controllers/customer_portal_controller.rb
class CustomerPortalController < ApplicationController
  layout 'customer_portal'
  
  skip_before_action :authenticate_user! # Customers don't need to be VMCOTT employees
  skip_before_action :verify_authenticity_token, only: [:authenticate]
  before_action :authenticate_customer, only: [:dashboard, :quotation, :approve, :status, :logout]
  before_action :set_customer_reception, only: [:dashboard, :status]
  before_action :set_quotation, only: [:quotation, :approve]
  before_action :authorize_quotation_access, only: [:quotation, :approve]
  
  # Helper methods for views
  helper_method :status_badge_color, :work_progress_percentage, :current_customer_reception

  def login
    # Customer enters their vehicle license plate and receipt number
    # Redirect to dashboard if already logged in
    if session[:customer_token].present? && current_customer_reception.present?
      redirect_to customer_dashboard_path and return
    end
  end

  def authenticate
    # Find vehicle first, then find reception by vehicle_id
    vehicle = Vehicle.find_by(license_plate: params[:license_plate])
    reception = ReceptionLog.find_by(
      vehicle_id: vehicle&.id,
      receipt_number: params[:receipt_number]
    )
    
    if reception
      # Generate temporary access token
      token = SecureRandom.hex(32)
      reception.update(
        portal_access_token: token,
        portal_access_expires_at: 7.days.from_now,
        customer_email: params[:email],
        customer_phone: params[:phone]
      )
      
      session[:customer_token] = token
      session[:customer_log_id] = reception.id
      
      redirect_to customer_dashboard_path, notice: "Welcome! You can track your vehicle repair here."
    else
      flash.now[:alert] = "Invalid license plate or receipt number. Please check and try again."
      render :login
    end
  end

  def dashboard
    @reception = @customer_reception
    @vehicle = @reception&.vehicle
    @condition_report = @reception&.condition_report
    
    # Find inspection by vehicle (since inspection has vehicle_id)
    @inspection = Inspection.find_by(vehicle: @vehicle) if @vehicle
    
    @jobs = @inspection&.inspection_jobs || []
    @parts_requests = @inspection&.parts_requests || []
    
    # Find quotation by vehicle (quotations have vehicle_id, not inspection_id)
    @quotation = Quotation.find_by(vehicle: @vehicle) if @vehicle
    
    @inspection_progress = work_progress_percentage(@inspection)
  end

  def quotation
    @quotation = Quotation.find(params[:id])
    # Find inspection by vehicle (since quotations have vehicle_id)
    @inspection = Inspection.find_by(vehicle: @quotation.vehicle) if @quotation.vehicle
    @jobs = @quotation.quotation_jobs
    @parts = @quotation.quotation_job_parts
    @total_cost = @quotation.amount || @quotation.quotation_jobs.sum(&:total_labor_cost) + @quotation.quotation_job_parts.sum(&:total_price)
  end

  def approve
    @quotation = Quotation.find(params[:id])
    
    if params[:approve_all].present?
      # Approve all jobs
      @quotation.quotation_jobs.update_all(client_approved: true, client_approved_at: Time.current)
      @quotation.update(status: 'approved', approved_at: Time.current)
      flash[:notice] = "All jobs approved. Work will begin shortly."
      
    elsif params[:approved_jobs].present?
      # Approve selected jobs
      approved_ids = params[:approved_jobs]
      @quotation.quotation_jobs.where(id: approved_ids).update_all(client_approved: true, client_approved_at: Time.current)
      @quotation.quotation_jobs.where.not(id: approved_ids).update_all(client_approved: false)
      
      if approved_ids.length == @quotation.quotation_jobs.count
        @quotation.update(status: 'approved', approved_at: Time.current)
        flash[:notice] = "All jobs approved. Work will begin shortly."
      else
        @quotation.update(status: 'partially_approved', approved_at: Time.current)
        flash[:notice] = "#{approved_ids.length} job(s) approved. The remaining jobs will not be performed."
      end
      
    else
      flash[:alert] = "Please select at least one job to approve."
      redirect_to customer_quotation_path(@quotation) and return
    end
    
    # Notify procurement that customer approved
    Notification.create!(
      title: "Quotation Approved by Customer",
      message: "Customer has approved #{@quotation.quotation_jobs.where(client_approved: true).count} out of #{@quotation.quotation_jobs.count} jobs for vehicle #{@quotation.vehicle&.license_plate}",
      link: "/vmcott/procurement/quotations/#{@quotation.id}",
      user_id: User.where(role: 'procurement').pluck(:id)
    )
    
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
    # Clear session
    session[:customer_token] = nil
    session[:customer_log_id] = nil
    redirect_to customer_login_path, notice: "You have been logged out."
  end

  private

  def authenticate_customer
    # Support both session token and URL parameter token
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
    
    # Store token in session if it came from URL parameter
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
    end
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
    
    # Check-in
    timeline << {
      date: reception.received_at,
      title: "Vehicle Received",
      description: "Your vehicle was received at VMCOTT",
      icon: "bi-box-arrow-in-right",
      status: "completed"
    }
    
    # Condition Report
    if reception.condition_report&.completed?
      timeline << {
        date: reception.condition_report.signed_at || reception.created_at,
        title: "Condition Report Completed",
        description: "Initial condition assessment completed",
        icon: "bi-clipboard-check",
        status: "completed"
      }
    end
    
    # Inspection
    if inspection.present?
      timeline << {
        date: inspection.created_at,
        title: "Inspection Started",
        description: "Technical inspection in progress",
        icon: "bi-search",
        status: inspection.status != 'pending_inspection' ? "completed" : "in_progress"
      }
      
      # Jobs
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
      
      # QC
      if inspection.status == 'ready_for_pickup' || inspection.status == 'completed'
        timeline << {
          date: inspection.ready_for_pickup_at || inspection.updated_at,
          title: "Quality Control Passed",
          description: "Vehicle passed quality control inspection",
          icon: "bi-check-circle",
          status: "completed"
        }
      end
      
      # Ready for Pickup
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

  # Helper methods
  def status_badge_color(status)
    case status.to_s
    when 'pending_inspection'
      'secondary'
    when 'approved_for_repair'
      'success'
    when 'in_progress'
      'warning'
    when 'parts_coordinator_review'
      'info'
    when 'ready_for_qc'
      'info'
    when 'qc_completed'
      'success'
    when 'ready_for_pickup'
      'success'
    when 'completed'
      'success'
    when 'approved'
      'success'
    when 'partially_approved'
      'warning'
    else
      'primary'
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