# app/controllers/vmcott/mechanic/dashboard_controller.rb
class Vmcott::Mechanic::DashboardController < ApplicationController
  # Skip the dashboard caching for this controller - THIS IS THE FIX!
  skip_around_action :cache_dashboard_data, if: :dashboard_controller?
  
  before_action :authenticate_user!
  before_action :require_mechanic
  before_action :set_job_context, only: [:show_job, :start_job, :update_progress, :log_parts, :request_qc, :request_part]
  before_action :ensure_can_take_job, only: [:assign_self]
  before_action :ensure_can_start_job, only: [:start_job]
  before_action :ensure_can_request_parts, only: [:log_parts, :request_part]
  
  # Disable all caching for this controller
  before_action :disable_caching

  def index
    # Set headers to prevent caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    # ========================================
    # MY CURRENT JOBS - What I'm working on
    # ========================================
    @my_jobs = MechanicAssignment.includes(inspection_job: { inspection: :vehicle })
                                 .where(mechanic_id: current_user.id, status: ['assigned', 'in_progress'])
                                 .order(created_at: :asc)

    # ========================================
    # READY TO START - Jobs I can take RIGHT NOW
    # ========================================
    @ready_jobs = InspectionJob.includes(inspection: :vehicle)
                               .where(assigned_mechanic_id: nil, completed_at: nil)
                               .where(verification_status: 'approved')
                               .where('requires_part_approval = false OR parts_approved = true')
                               .joins(:inspection)
                               .where(inspections: { status: 'approved_for_repair' })
                               .order(created_at: :asc)
                               .limit(20)

    # ========================================
    # WAITING JOBS - All jobs that aren't ready yet
    # ========================================
    @waiting_jobs = InspectionJob.includes(inspection: :vehicle)
                                 .where(assigned_mechanic_id: nil, completed_at: nil)
                                 .where.not(
                                   id: @ready_jobs.select(:id)
                                 )
                                 .order(created_at: :desc)
                                 .limit(20)

    # ========================================
    # TAKEN BY OTHERS - Jobs other mechanics are doing
    # ========================================
    @other_mechanics_jobs = InspectionJob.includes(inspection: :vehicle)
                                         .where.not(assigned_mechanic_id: nil)
                                         .where.not(assigned_mechanic_id: current_user.id)
                                         .where(completed_at: nil)
                                         .order(created_at: :desc)
                                         .limit(20)

    # ========================================
    # QC PENDING JOBS - Jobs that need quality check
    # ========================================
    @pending_qc_jobs = InspectionJob.includes(inspection: { vehicle: :agency })
                                .joins(:inspection)
                                .where.not(completed_at: nil)
                                .where(inspections: { status: ['pending_mechanic_review', 'parts_coordinator_review', 'approved_for_repair', 'ready_for_qc'] })
                                .order(completed_at: :desc)
                                .limit(20)

    # ========================================
    # STATS CARDS - Quick numbers
    # ========================================
    @completed_today = MechanicAssignment.where(mechanic_id: current_user.id)
                                         .where('completed_at >= ?', Date.current.beginning_of_day)
                                         .count
    
    @pending_qc = @pending_qc_jobs.count
                           
    @recently_completed = InspectionJob.where(assigned_mechanic_id: current_user.id)
                                       .where.not(completed_at: nil)
                                       .order(completed_at: :desc)
                                       .limit(10)

    # For backward compatibility
    @assigned_jobs = @my_jobs
    @taken_jobs = @other_mechanics_jobs
    @ready_to_take_jobs = @ready_jobs
    @not_ready_jobs = @waiting_jobs
    
  rescue => e
    Rails.logger.error "Error in mechanic dashboard: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    flash[:alert] = "An error occurred while loading the dashboard: #{e.message}"
    
    @my_jobs = []
    @ready_jobs = []
    @waiting_jobs = []
    @other_mechanics_jobs = []
    @pending_qc_jobs = []
    @completed_today = 0
    @pending_qc = 0
    @recently_completed = []
    @assigned_jobs = []
    @taken_jobs = []
    @ready_to_take_jobs = []
    @not_ready_jobs = []
  end

  def verification_queue
    # Disable caching for this action
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    @jobs_needing_verification = InspectionJob.includes(inspection: :vehicle)
                                              .where(assigned_mechanic_id: nil, 
                                                     completed_at: nil,
                                                     verification_status: 'pending')
                                              .order(created_at: :asc)
    render 'vmcott/mechanic/dashboard/verification_queue'
  end

  def verify_job
    @job = InspectionJob.includes(inspection: :vehicle, inspection_job_parts: :part).find(params[:id])
    
    if @job.assigned_mechanic_id.present? && @job.assigned_mechanic_id != current_user.id
      redirect_to vmcott_mechanic_dashboard_path, alert: "This job is already assigned to another mechanic."
      return
    end
    
    @job.update(assigned_mechanic_id: current_user.id) if @job.assigned_mechanic_id.nil?
    
    # Disable caching for this action
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    render 'vmcott/mechanic/dashboard/verify_job'
  end

  def submit_verification
    @job = InspectionJob.find(params[:id])
    
    if @job.assigned_mechanic_id != current_user.id
      redirect_to vmcott_mechanic_dashboard_path, alert: "You cannot verify a job that isn't assigned to you."
      return
    end

    ActiveRecord::Base.transaction do
      verification_status = params[:verification_status]
      
      @job.update!(
        verification_status: verification_status,
        verified_by_mechanic_id: current_user.id,
        verified_at: Time.current,
        mechanic_notes: params[:mechanic_notes]
      )

      case verification_status
      when 'verified'
        @job.inspection_job_parts.each do |job_part|
          part = job_part.part
          if part && part.current_stock >= job_part.quantity
            PartsRequest.create!(
              inspection: @job.inspection,
              inspection_job: @job,
              part: part,
              quantity: job_part.quantity,
              status: 'approved',
              in_stock: true
            )
          else
            PartsRequest.create!(
              inspection: @job.inspection,
              inspection_job: @job,
              part: part,
              quantity: job_part.quantity,
              status: 'pending',
              in_stock: false,
              custom_part_name: job_part.custom_part_name
            )
          end
        end
        
        flash[:notice] = "Job verified successfully. Parts requests created."
        
      when 'different'
        corrected_job = @job.inspection.inspection_jobs.create!(
          description: params[:corrected_description],
          recommendation_source: 'mechanic',
          verification_status: 'approved',
          parent_job_id: @job.id,
          priority: @job.priority
        )
        
        if params[:parts].present?
          params[:parts].each do |part_data|
            if part_data[:is_custom] == 'true'
              corrected_job.inspection_job_parts.create!(
                custom_part_name: part_data[:custom_name],
                quantity: part_data[:quantity]
              )
              PartsRequest.create!(
                inspection: @job.inspection,
                inspection_job: corrected_job,
                custom_part_name: part_data[:custom_name],
                quantity: part_data[:quantity],
                status: 'pending',
                in_stock: false
              )
            else
              part = Part.find(part_data[:part_id])
              corrected_job.inspection_job_parts.create!(
                part: part,
                quantity: part_data[:quantity]
              )
              
              if part.current_stock >= part_data[:quantity].to_i
                PartsRequest.create!(
                  inspection: @job.inspection,
                  inspection_job: corrected_job,
                  part: part,
                  quantity: part_data[:quantity],
                  status: 'approved',
                  in_stock: true
                )
              else
                PartsRequest.create!(
                  inspection: @job.inspection,
                  inspection_job: corrected_job,
                  part: part,
                  quantity: part_data[:quantity],
                  status: 'pending',
                  in_stock: false
                )
              end
            end
          end
        end
        
        @job.update!(status: 'superseded')
        flash[:notice] = "Corrected job created based on your findings."
        
      when 'rejected'
        @job.update!(
          completed_at: Time.current,
          status: 'cancelled'
        )
        flash[:notice] = "Job marked as not needed."
      end

      inspection = @job.inspection
      if inspection.inspection_jobs.where(verification_status: 'pending').none?
        if inspection.inspection_jobs.joins(:parts_requests).where(parts_requests: { status: 'pending' }).any?
          inspection.update!(status: 'parts_coordinator_review')
          notify_parts_coordinator(inspection)
        else
          inspection.update!(status: 'approved_for_repair')
          notify_mechanics_work_ready(inspection)
        end
      end
    end

    redirect_to vmcott_mechanic_dashboard_path
  rescue => e
    Rails.logger.error "Error in submit_verification: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    flash[:alert] = "An error occurred while submitting verification: #{e.message}"
    redirect_to vmcott_mechanic_verify_job_path(@job)
  end

  def new_additional_finding
    @inspection = Inspection.find(params[:inspection_id])
    
    # Disable caching for this action
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    # Ensure we're not trying to modify an already-approved job
    unless @inspection.approved_for_repair?
      redirect_to vmcott_mechanic_dashboard_path, alert: "Can only report additional findings on approved work."
      return
    end
    
    @job = @inspection.inspection_jobs.new
    render 'vmcott/mechanic/dashboard/new_additional_finding'
  end

  # ========================================
  # FIXED: create_additional_finding - With proper attributes
  # ========================================
  def create_additional_finding
    @inspection = Inspection.find(params[:inspection_id])
    @job = InspectionJob.find_by(inspection_id: @inspection.id)
    
    # Create a new maintenance record for additional work with valid attributes
    additional_maintenance = @inspection.vehicle.maintenances.create!(
      service_type: "Additional Finding",
      description: params[:description],
      status: "Pending",
      assignment_type: "stores",  # Required field - valid values: 'stores' or 'purchasing'
      date: Time.current,
      start_date: Time.current,
      end_date: 7.days.from_now,
      notes: "Additional finding during repair of inspection ##{@inspection.id}",
      additional_work: true,
      urgency: :high
    )
    
    # Notify finance for new quotation
    notify_finance_for_additional_quotation(additional_maintenance)
    
    # Redirect back to the job page
    if @job.present?
      redirect_to vmcott_mechanic_job_path(@job), notice: "Additional finding logged. Finance will create a new quotation."
    else
      redirect_to vmcott_mechanic_dashboard_path, notice: "Additional finding logged. Finance will create a new quotation."
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Validation error in create_additional_finding: #{e.message}"
    Rails.logger.error e.record.errors.full_messages.join(", ")
    
    if @job.present?
      redirect_to vmcott_mechanic_job_path(@job), alert: "Failed to log additional finding: #{e.record.errors.full_messages.join(', ')}"
    else
      redirect_to vmcott_mechanic_dashboard_path, alert: "Failed to log additional finding: #{e.record.errors.full_messages.join(', ')}"
    end
  rescue => e
    Rails.logger.error "Error in create_additional_finding: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    
    if @job.present?
      redirect_to vmcott_mechanic_job_path(@job), alert: "An error occurred: #{e.message}"
    else
      redirect_to vmcott_mechanic_dashboard_path, alert: "An error occurred: #{e.message}"
    end
  end

  # ========================================
  # FIXED: assign_self - Uses update_columns to bypass validation
  # ========================================
  def assign_self
    job = InspectionJob.find_by(id: params[:id])
    
    if job.nil?
      redirect_to vmcott_mechanic_dashboard_path, alert: "Job not found."
      return
    end
    
    # Only allow taking jobs that are ready
    unless job.verification_status == 'approved' && job.inspection&.approved_for_repair?
      redirect_to vmcott_mechanic_dashboard_path, alert: "This job is not ready to be taken yet."
      return
    end
    
    if job.assigned_mechanic_id.present? && job.assigned_mechanic_id != current_user.id
      assigned_mechanic = User.find_by(id: job.assigned_mechanic_id)
      redirect_to vmcott_mechanic_dashboard_path, alert: "This job is already assigned to #{assigned_mechanic&.name || 'another mechanic'}."
      return
    end
    
    # Use update_columns to bypass validation
    job.update_columns(assigned_mechanic_id: current_user.id)
    
    assignment = MechanicAssignment.find_or_initialize_by(
      inspection_job_id: job.id,
      mechanic_id: current_user.id
    )
    
    if assignment.new_record?
      assignment.status = 'assigned'
      assignment.started_at = Time.current
      assignment.save!
    end
    
    redirect_to vmcott_mechanic_job_path(job), notice: "Job assigned to you successfully."
  rescue => e
    Rails.logger.error "Error in assign_self: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    redirect_to vmcott_mechanic_dashboard_path, alert: "An error occurred while assigning the job: #{e.message}"
  end

  # ========================================
  # FIXED: start_job
  # ========================================
  def start_job
    if @job.assigned_mechanic_id != current_user.id
      redirect_to vmcott_mechanic_dashboard_path, alert: "You cannot start a job that isn't assigned to you."
      return
    end
    
    # Ensure job is approved
    unless @job.inspection&.approved_for_repair?
      redirect_to vmcott_mechanic_job_path(@job), alert: "This job is not approved for work yet."
      return
    end
    
    assignment = MechanicAssignment.find_or_initialize_by(
      inspection_job_id: @job.id,
      mechanic_id: current_user.id
    )
    
    assignment.status = 'in_progress'
    assignment.started_at = Time.current
    assignment.save!
    
    redirect_to vmcott_mechanic_job_path(@job), notice: "Job started successfully. Good luck!"
  rescue => e
    Rails.logger.error "Error in start_job: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    redirect_to vmcott_mechanic_job_path(@job), alert: "An error occurred while starting the job: #{e.message}"
  end

  def update_progress
    if @job.assigned_mechanic_id != current_user.id
      redirect_to vmcott_mechanic_dashboard_path, alert: "You cannot update a job that isn't assigned to you."
      return
    end
    
    if params[:progress_update].blank?
      redirect_to vmcott_mechanic_job_path(@job), alert: "Progress note cannot be blank."
      return
    end
    
    assignment = MechanicAssignment.find_by(inspection_job_id: @job.id, mechanic_id: current_user.id)
    
    if assignment.nil?
      redirect_to vmcott_mechanic_job_path(@job), alert: "Assignment record not found."
      return
    end
    
    assignment.update(
      mechanic_notes: "#{assignment.mechanic_notes}\n[#{Time.current.strftime('%H:%M %m/%d')}] #{params[:progress_update]}"
    )
    
    flash[:notice] = "Progress updated successfully."
    redirect_to vmcott_mechanic_job_path(@job)
  rescue => e
    Rails.logger.error "Error in update_progress: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    redirect_to vmcott_mechanic_job_path(@job), alert: "An error occurred while updating progress: #{e.message}"
  end

  def log_parts
    if @job.assigned_mechanic_id != current_user.id
      render json: { success: false, message: "You cannot log parts for a job that isn't assigned to you." }, status: :unauthorized
      return
    end
    
    # Only allow logging parts when job is in progress
    assignment = MechanicAssignment.find_by(inspection_job_id: @job.id, mechanic_id: current_user.id)
    unless assignment&.in_progress?
      render json: { success: false, message: "Parts can only be logged when job is in progress." }, status: :unauthorized
      return
    end
    
    part = Part.find_by(id: params[:part_id])
    qty = params[:quantity].to_i

    if part.nil?
      render json: { success: false, message: "Part not found" }, status: :not_found
      return
    end

    if qty <= 0
      render json: { success: false, message: "Quantity must be greater than zero" }, status: :unprocessable_entity
      return
    end

    if part.current_stock < qty
      render json: { success: false, message: "Insufficient stock. Available: #{part.current_stock}" }, status: :unprocessable_entity
      return
    end

    part.update!(current_stock: part.current_stock - qty)
    
    if assignment
      assignment.update(
        mechanic_notes: "#{assignment.mechanic_notes}\n[PARTS] Used #{qty}x #{part.name} (Stock left: #{part.current_stock})"
      )
    end
    
    job_part = InspectionJobPart.find_or_create_by!(
      inspection_job_id: @job.id,
      part_id: part.id
    ) do |jp|
      jp.quantity = qty
      jp.notes = "Used by mechanic #{current_user.name}"
    end

    render json: { success: true, new_stock: part.current_stock, message: "#{qty}x #{part.name} logged successfully" }
  rescue => e
    Rails.logger.error "Error in log_parts: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: { success: false, message: "An error occurred: #{e.message}" }, status: :internal_server_error
  end

  # ========================
  # FIXED: request_part - No more notes attribute
  # ========================
  def request_part
    if @job.assigned_mechanic_id != current_user.id
      redirect_to vmcott_mechanic_dashboard_path, alert: "You cannot request parts for a job that isn't assigned to you."
      return
    end
    
    assignment = MechanicAssignment.find_by(inspection_job_id: @job.id, mechanic_id: current_user.id)
    unless assignment&.in_progress?
      redirect_to vmcott_mechanic_job_path(@job), alert: "Parts can only be requested when job is in progress."
      return
    end

    # Check if we have the required fields
    if params[:quantity].blank? || params[:quantity].to_i <= 0
      redirect_to vmcott_mechanic_job_path(@job), alert: "Please enter a valid quantity."
      return
    end

    # Handle based on part type
    if params[:part_type] == 'inventory'
      # Inventory part request
      if params[:part_id].blank?
        redirect_to vmcott_mechanic_job_path(@job), alert: "Please select a part from the inventory."
        return
      end
      
      part = Part.find_by(id: params[:part_id])
      if part.nil?
        redirect_to vmcott_mechanic_job_path(@job), alert: "Selected part not found."
        return
      end
      
      parts_request = PartsRequest.new(
        inspection_id: params[:inspection_id],
        inspection_job_id: params[:inspection_job_id],
        part_id: part.id,
        quantity: params[:quantity],
        status: part.current_stock >= params[:quantity].to_i ? 'approved' : 'pending',
        in_stock: part.current_stock >= params[:quantity].to_i
      )
      
    elsif params[:part_type] == 'custom'
      # Custom part request
      if params[:custom_part_name].blank?
        redirect_to vmcott_mechanic_job_path(@job), alert: "Please enter a name for the custom part."
        return
      end
      
      parts_request = PartsRequest.new(
        inspection_id: params[:inspection_id],
        inspection_job_id: params[:inspection_job_id],
        custom_part_name: params[:custom_part_name],
        quantity: params[:quantity],
        status: 'pending',
        in_stock: false
      )
    else
      redirect_to vmcott_mechanic_job_path(@job), alert: "Please select a part type."
      return
    end

    if parts_request.save
      # Update assignment notes
      part_name = part&.name || params[:custom_part_name]
      assignment.update(
        mechanic_notes: "#{assignment.mechanic_notes}\n[REQUEST] Requested #{params[:quantity]}x #{part_name}"
      )
      
      # Notify parts coordinator
      notify_parts_coordinator(@job.inspection) if parts_request.status == 'pending'
      
      redirect_to vmcott_mechanic_job_path(@job), notice: "Parts request submitted successfully."
    else
      redirect_to vmcott_mechanic_job_path(@job), alert: "Failed to create parts request: #{parts_request.errors.full_messages.join(', ')}"
    end
  rescue => e
    Rails.logger.error "Error in request_part: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    redirect_to vmcott_mechanic_job_path(@job), alert: "An error occurred: #{e.message}"
  end

  def request_qc
    if @job.assigned_mechanic_id != current_user.id
      redirect_to vmcott_mechanic_dashboard_path, alert: "You cannot request QC for a job that isn't assigned to you."
      return
    end
    
    inspection = @job&.inspection
    
    if @job.nil? || inspection.nil?
      redirect_to vmcott_mechanic_dashboard_path, alert: "Job or inspection not found."
      return
    end
    
    assignment = MechanicAssignment.find_by(inspection_job_id: @job.id, mechanic_id: current_user.id)
    if assignment
      assignment.update!(
        status: 'completed', 
        completed_at: Time.current
      )
    end
    
    @job.update_columns(completed_at: Time.current)

    if inspection.inspection_jobs.where(completed_at: nil).none?
      inspection.update!(status: 'ready_for_qc')
      
      User.where(role: ['inspector', 'admin']).each do |inspector|
        Notification.create!(
          user: inspector,
          title: "QC Required for #{inspection.vehicle&.license_plate || 'Vehicle'}",
          message: "All jobs for inspection ##{inspection.id} are completed. Please perform final QC.",
          notifiable: inspection,
          link: vmcott_inspector_qc_path(inspection)
        ) rescue nil
      end
      
      flash[:notice] = "Job completed and QC requested. All jobs for this vehicle are now complete."
    else
      flash[:notice] = "Job completed. Other jobs for this vehicle are still in progress."
    end

    redirect_to vmcott_mechanic_dashboard_path
  rescue => e
    Rails.logger.error "Error in request_qc: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    redirect_to vmcott_mechanic_job_path(@job), alert: "An error occurred while requesting QC: #{e.message}"
  end

  private

  def require_mechanic
    unless current_user.mechanic? || current_user.maintenance_supervisor? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Mechanic privileges required."
    end
  end

  def set_job_context
    @job = InspectionJob.includes(inspection: :vehicle).find_by(id: params[:id])
    
    if @job.nil?
      flash[:alert] = "Job not found."
      redirect_to vmcott_mechanic_dashboard_path and return false
    end
    
    if @job.assigned_mechanic_id == current_user.id
      @assignment = MechanicAssignment.find_or_initialize_by(
        inspection_job_id: @job.id,
        mechanic_id: current_user.id
      )
      
      if @assignment.new_record?
        @assignment.status = 'assigned'
        @assignment.started_at = Time.current
        @assignment.save!
      end
    else
      @assignment = MechanicAssignment.find_by(
        inspection_job_id: @job.id,
        mechanic_id: @job.assigned_mechanic_id
      )
    end
    
    true
  end

  def ensure_can_take_job
    job = InspectionJob.find_by(id: params[:id])
    return unless job
    
    unless job.verification_status == 'approved' && job.inspection&.approved_for_repair?
      redirect_to vmcott_mechanic_dashboard_path, alert: "This job is not ready to be taken."
      return false
    end
  end

  def ensure_can_start_job
    return unless @job
    
    unless @job.inspection&.approved_for_repair?
      redirect_to vmcott_mechanic_job_path(@job), alert: "This job is not approved for work yet."
      return false
    end
  end

  def ensure_can_request_parts
    return unless @job
    
    assignment = MechanicAssignment.find_by(inspection_job_id: @job.id, mechanic_id: current_user.id)
    unless assignment&.in_progress?
      flash[:alert] = "Parts can only be requested when job is in progress."
      redirect_to vmcott_mechanic_job_path(@job) and return false
    end
    true
  end

  def notify_parts_coordinator(inspection)
    coordinator_ids = User.where(role: 'parts_coordinator').pluck(:id)
    Notification.create!(
      title: "Parts Required",
      message: "Inspection ##{inspection.id} for #{inspection.vehicle.license_plate} has parts that need ordering.",
      link: "/vmcott/parts_coordinator/dashboard",
      user_id: coordinator_ids,
      notifiable_type: 'Inspection',
      notifiable_id: inspection.id
    )
  rescue => e
    Rails.logger.error "Failed to create notification: #{e.message}"
  end

  def notify_mechanics_work_ready(inspection)
    mechanic_ids = User.where(role: 'mechanic').pluck(:id)
    Notification.create!(
      title: "Work Ready",
      message: "Inspection ##{inspection.id} for #{inspection.vehicle.license_plate} is ready for work.",
      link: "/vmcott/mechanic/dashboard",
      user_id: mechanic_ids,
      notifiable_type: 'Inspection',
      notifiable_id: inspection.id
    )
  rescue => e
    Rails.logger.error "Failed to create notification: #{e.message}"
  end

  def notify_finance_for_additional_quotation(maintenance)
    finance_users = User.where(role: ['finance', 'admin']).pluck(:id)
    Notification.create!(
      title: "Additional Work Requires Quotation",
      message: "Additional work '#{maintenance.description}' needs a quotation for the agency.",
      link: "/vmcott/finance/quotations/new_for_maintenance/#{maintenance.id}",
      user_id: finance_users,
      notifiable_type: 'Maintenance',
      notifiable_id: maintenance.id
    )
  rescue => e
    Rails.logger.error "Failed to create notification: #{e.message}"
  end

  # Add this method to disable caching for all actions
  def disable_caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end

  # ========================================
  # HELPER METHODS FOR HUMAN-READABLE STATUSES
  # ========================================
  helper_method :job_status, :job_status_color, :waiting_status, :waiting_status_color

  def job_status(job, assignment = nil)
    if job.completed_at
      return "✅ Completed"
    end
    
    if assignment&.started_at
      return "🔧 In Progress"
    end
    
    if job.assigned_mechanic_id.present?
      return "📋 Assigned"
    end
    
    if job.verification_status == 'approved' && job.inspection&.approved_for_repair?
      return "✅ Ready to Start"
    end
    
    waiting_status(job)
  end

  def job_status_color(job, assignment = nil)
    if job.completed_at
      return 'success'
    end
    
    if assignment&.started_at
      return 'warning'
    end
    
    if job.assigned_mechanic_id.present?
      return 'info'
    end
    
    if job.verification_status == 'approved' && job.inspection&.approved_for_repair?
      return 'success'
    end
    
    waiting_status_color(job)
  end

  def waiting_status(job)
    if job.verification_status != 'approved'
      return "⏳ Waiting for inspector"
    end
    
    case job.inspection&.status
    when 'pending_inspection'
      return "⏳ Waiting for inspection"
    when 'inspection_in_progress'
      return "🔍 Inspector working"
    when 'pending_mechanic_review'
      return "📝 Waiting for mechanic review"
    when 'parts_coordinator_review'
      return "📦 Parts coordinator reviewing"
    when 'awaiting_parts'
      return "📦 Waiting for parts"
    when 'ready_for_qc'
      return "✅ Ready for QC"
    when 'qc_completed'
      return "✅ QC completed"
    when 'completed'
      return "✅ Already completed"
    when 'cancelled_by_agency'
      return "❌ Cancelled by agency"
    else
      return "⏳ Waiting for approval"
    end
  end

  def waiting_status_color(job)
    if job.verification_status != 'approved'
      return 'warning'
    end
    
    case job.inspection&.status
    when 'pending_inspection', 'inspection_in_progress'
      return 'info'
    when 'pending_mechanic_review'
      return 'primary'
    when 'parts_coordinator_review', 'awaiting_parts'
      return 'warning'
    when 'ready_for_qc', 'qc_completed'
      return 'success'
    when 'cancelled_by_agency'
      return 'danger'
    else
      return 'secondary'
    end
  end
end