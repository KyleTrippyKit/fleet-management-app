# app/controllers/vmcott/mechanic/dashboard_controller.rb
class Vmcott::Mechanic::DashboardController < ApplicationController
  # Skip the dashboard caching for this controller
  skip_around_action :cache_dashboard_data, if: :dashboard_controller?
  
  before_action :authenticate_user!
  before_action :require_mechanic
  before_action :set_job_context, only: [:show_job, :start_job, :update_progress, :log_parts, :request_qc, :request_part, :start_pre_check, :submit_pre_check]
  before_action :ensure_can_start_job, only: [:start_job]
  before_action :ensure_can_request_parts, only: [:log_parts, :request_part]
  before_action :ensure_can_do_pre_check, only: [:start_pre_check, :submit_pre_check]
  
  # Disable all caching for this controller
  before_action :disable_caching

  def index
    # Set headers to prevent caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    # ========================================
    # MY ASSIGNED JOBS - What supervisor assigned to me
    # ========================================
    @assigned_jobs = MechanicAssignment.includes(inspection_job: { inspection: :vehicle })
                                       .where(mechanic_id: current_user.id, status: ['assigned', 'in_progress'])
                                       .order(created_at: :asc)

    # ========================================
    # JOBS NEEDING PRE-CHECK - Jobs assigned but not pre-checked
    # ========================================
    @pre_check_jobs = InspectionJob.includes(inspection: :vehicle)
                                   .where(assigned_mechanic_id: current_user.id)
                                   .where(status: 'assigned')
                                   .order(created_at: :asc)

    # ========================================
    # JOBS READY FOR WORK - Pre-check completed and approved
    # ========================================
    @ready_for_work = InspectionJob.includes(inspection: :vehicle)
                                   .where(assigned_mechanic_id: current_user.id)
                                   .where(status: 'approved_for_work')
                                   .order(created_at: :asc)

    # ========================================
    # WAITING JOBS - Jobs assigned to others or pending approval
    # ========================================
    @waiting_jobs = InspectionJob.includes(inspection: :vehicle)
                                 .where(assigned_mechanic_id: nil, completed_at: nil)
                                 .where(verification_status: 'approved')
                                 .joins(:inspection)
                                 .where(inspections: { status: 'approved_for_repair' })
                                 .where.not(id: @assigned_jobs.map(&:inspection_job_id))
                                 .distinct
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
    @pre_check_needed = @pre_check_jobs.count
    @ready_to_work = @ready_for_work.count
                           
    @recently_completed = InspectionJob.where(assigned_mechanic_id: current_user.id)
                                       .where.not(completed_at: nil)
                                       .order(completed_at: :desc)
                                       .limit(10)

    # ========================================
    # WORKFLOW STATUS VARIABLES
    # ========================================
    @inspections_complete = Inspection.where(status: ['approved_for_repair', 'ready_for_qc', 'qc_completed']).count
    @parts_complete = PartsRequest.where(status: ['approved', 'parts_received']).count
    @parts_pending = PartsRequest.where(status: ['pending_approval', 'parts_coordinator_notified']).count
    @assigned_jobs_count = @assigned_jobs.count
    @available_jobs_count = InspectionJob.where(assigned_mechanic_id: nil, completed_at: nil)
                                         .where(verification_status: 'approved')
                                         .joins(:inspection)
                                         .where(inspections: { status: 'approved_for_repair' })
                                         .count
    
    @repairs_complete = InspectionJob.where.not(completed_at: nil)
                                     .where('inspection_jobs.completed_at >= ?', Time.current.beginning_of_day)
                                     .count
    
    @qc_complete = InspectionJob.where(verification_status: 'verified')
                                .where('inspection_jobs.verified_at > ?', 24.hours.ago)
                                .count
    
    @ready_for_pickup = Inspection.where(status: 'ready_for_pickup').count
    
    @new_jobs_available = @waiting_jobs.where('inspection_jobs.created_at > ?', 1.hour.ago).count

    # For backward compatibility
    @my_jobs = @assigned_jobs
    @taken_jobs = @other_mechanics_jobs
    @ready_to_take_jobs = @waiting_jobs
    @not_ready_jobs = []
    
  rescue => e
    Rails.logger.error "Error in mechanic dashboard: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    flash[:alert] = "An error occurred while loading the dashboard: #{e.message}"
    
    @assigned_jobs = []
    @pre_check_jobs = []
    @ready_for_work = []
    @waiting_jobs = []
    @other_mechanics_jobs = []
    @pending_qc_jobs = []
    @completed_today = 0
    @pending_qc = 0
    @pre_check_needed = 0
    @ready_to_work = 0
    @recently_completed = []
    @my_jobs = []
    @taken_jobs = []
    @ready_to_take_jobs = []
    @not_ready_jobs = []
    @inspections_complete = 0
    @parts_complete = 0
    @parts_pending = 0
    @assigned_jobs_count = 0
    @available_jobs_count = 0
    @repairs_complete = 0
    @qc_complete = 0
    @ready_for_pickup = 0
    @new_jobs_available = 0
  end

  def show_job
    @job = InspectionJob.includes(inspection: :vehicle, parts_requests: [:part])
                        .find(params[:id])
    @assignment = MechanicAssignment.find_by(inspection_job_id: @job.id, mechanic_id: current_user.id)
    @parts_used = @job.parts_requests.where(status: ['parts_received', 'used', 'installed', 'completed'])
    @pre_check_data = {
      notes: @job.pre_check_notes,
      completed_at: @job.pre_check_completed_at,
      findings: @job.additional_findings
    }
    
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end

  # 🔥 FIX: Mechanics cannot self-assign jobs - only supervisor can assign
  def assign_self
    redirect_to vmcott_mechanic_dashboard_path, 
                alert: "❌ Jobs are assigned by the workshop supervisor only. You will see assigned jobs in your dashboard."
    return
  end

  # =====================================================
  # PRE-CHECK METHODS
  # =====================================================
  
  def start_pre_check
    @job = InspectionJob.find(params[:id])
    
    unless @job.assigned_mechanic_id == current_user.id
      redirect_to vmcott_mechanic_dashboard_path, alert: "You cannot start pre-check for a job not assigned to you."
      return
    end
    
    unless @job.status == 'assigned'
      redirect_to vmcott_mechanic_job_path(@job), alert: "This job is not ready for pre-check."
      return
    end
    
    @job.start_pre_check!(current_user)
    
    redirect_to pre_check_vmcott_mechanic_job_path(@job), notice: "Pre-check started. Please inspect the vehicle thoroughly."
  end

  def pre_check
    @job = InspectionJob.find(params[:id])
    
    unless @job.assigned_mechanic_id == current_user.id
      redirect_to vmcott_mechanic_dashboard_path, alert: "Access denied."
      return
    end
    
    unless @job.status == 'pre_check_in_progress'
      redirect_to vmcott_mechanic_job_path(@job), alert: "Pre-check not in progress."
      return
    end
    
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    render :pre_check
  end

  def submit_pre_check
    @job = InspectionJob.find(params[:id])
    
    unless @job.assigned_mechanic_id == current_user.id
      redirect_to vmcott_mechanic_dashboard_path, alert: "Access denied."
      return
    end
    
    additional_findings = []
    
    if params[:additional_findings].present?
      additional_findings = params[:additional_findings].map do |finding|
        {
          description: finding[:description],
          severity: finding[:severity],
          estimated_hours: finding[:estimated_hours],
          created_at: Time.current,
          created_by: current_user.name
        }
      end
    end
    
    @job.complete_pre_check!(params[:notes], additional_findings)
    
    redirect_to vmcott_mechanic_dashboard_path, 
                notice: "✅ Pre-check completed. #{additional_findings.count} additional findings sent to supervisor for approval."
  end

  def start_job
    if @job.assigned_mechanic_id != current_user.id
      redirect_to vmcott_mechanic_dashboard_path, alert: "You cannot start a job that isn't assigned to you."
      return
    end
    
    unless @job.status == 'approved_for_work'
      redirect_to vmcott_mechanic_job_path(@job), alert: "This job is not approved for work yet. Complete pre-check first."
      return
    end
    
    assignment = MechanicAssignment.find_or_initialize_by(
      inspection_job_id: @job.id,
      mechanic_id: current_user.id
    )
    
    assignment.status = 'in_progress'
    assignment.started_at = Time.current
    assignment.save!
    
    @job.update!(started_at: Time.current, status: :in_progress)
    
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

  def request_part
    if @job.assigned_mechanic_id != current_user.id
      redirect_to vmcott_mechanic_dashboard_path, alert: "Access Denied: You cannot request parts for a job that isn't assigned to you."
      return
    end
    
    assignment = MechanicAssignment.find_by(inspection_job_id: @job.id, mechanic_id: current_user.id)
    unless assignment&.in_progress?
      redirect_to vmcott_mechanic_job_path(@job), alert: "Action Not Permitted: Parts can only be requested when job is in progress."
      return
    end

    if params[:quantity].blank? || params[:quantity].to_i <= 0
      redirect_to vmcott_mechanic_job_path(@job), alert: "Invalid Quantity: Please enter a valid quantity greater than zero."
      return
    end

    quantity = params[:quantity].to_i

    if params[:part_type] == 'inventory'
      if params[:part_id].blank?
        redirect_to vmcott_mechanic_job_path(@job), alert: "Selection Required: Please select a part from the inventory."
        return
      end
      
      part = Part.find_by(id: params[:part_id])
      if part.nil?
        redirect_to vmcott_mechanic_job_path(@job), alert: "Part Not Found: The selected part could not be located in the inventory."
        return
      end
      
      part_name = part.name
      
      existing_request = PartsRequest.find_by(
        inspection_id: @job.inspection_id,
        part_id: part.id,
        status: 'pending_approval'
      )
      
      if existing_request
        new_quantity = existing_request.quantity + quantity
        existing_request.update(quantity: new_quantity)
        
        assignment.update(
          mechanic_notes: "#{assignment.mechanic_notes}\n[REQUEST] Added #{quantity}x #{part_name} to existing request (Total: #{new_quantity})"
        )
        
        flash[:notice] = "✅ Quantity Updated\n\n" \
                        "Part: #{part_name}\n" \
                        "Added: #{quantity} units\n" \
                        "Total: #{new_quantity} units\n\n" \
                        "Waiting for supervisor approval."
      else
        # Create new parts request
        parts_request = @job.request_part!({
          part_id: part.id,
          part_name: part_name,
          quantity: quantity,
          notes: params[:notes]
        }, current_user)
        
        assignment.update(
          mechanic_notes: "#{assignment.mechanic_notes}\n[REQUEST] Requested #{quantity}x #{part_name}"
        )
        
        flash[:notice] = "📋 Request Submitted\n\n" \
                        "Part: #{part_name}\n" \
                        "Quantity: #{quantity} units\n\n" \
                        "Waiting for supervisor approval."
      end
      
    elsif params[:part_type] == 'custom'
      if params[:custom_part_name].blank?
        redirect_to vmcott_mechanic_job_path(@job), alert: "Required Field: Please enter a name for the custom part."
        return
      end
      
      part_name = params[:custom_part_name]
      
      existing_request = PartsRequest.find_by(
        inspection_id: @job.inspection_id,
        custom_part_name: part_name,
        status: 'pending_approval'
      )
      
      if existing_request
        new_quantity = existing_request.quantity + quantity
        existing_request.update(quantity: new_quantity)
        
        assignment.update(
          mechanic_notes: "#{assignment.mechanic_notes}\n[REQUEST] Added #{quantity}x #{part_name} (custom) to existing request (Total: #{new_quantity})"
        )
        
        flash[:notice] = "✅ Quantity Updated\n\n" \
                        "Part: #{part_name} (Custom)\n" \
                        "Added: #{quantity} units\n" \
                        "Total: #{new_quantity} units\n\n" \
                        "Waiting for supervisor approval."
      else
        parts_request = @job.request_part!({
          custom_part_name: part_name,
          part_name: part_name,
          quantity: quantity,
          notes: params[:notes]
        }, current_user)
        
        assignment.update(
          mechanic_notes: "#{assignment.mechanic_notes}\n[REQUEST] Requested #{quantity}x #{part_name} (custom part)"
        )
        
        flash[:notice] = "📦 Request Submitted\n\n" \
                        "Part: #{part_name} (Custom)\n" \
                        "Quantity: #{quantity} units\n\n" \
                        "Supervisor has been notified."
      end
    else
      redirect_to vmcott_mechanic_job_path(@job), alert: "Selection Required: Please select a part type (Inventory or Custom)."
      return
    end

    redirect_to vmcott_mechanic_job_path(@job), notice: flash[:notice]
  rescue => e
    Rails.logger.error "Error in request_part: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    redirect_to vmcott_mechanic_job_path(@job), alert: "System Error: An unexpected error occurred. Please contact support."
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
    
    flash[:highlight_job_id] = @job.id
    flash[:success] = "Job ##{@job.id} has been marked complete and sent for QC inspection"

    redirect_to vmcott_mechanic_dashboard_path
  rescue => e
    Rails.logger.error "Error in request_qc: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    redirect_to vmcott_mechanic_job_path(@job), alert: "An error occurred while requesting QC: #{e.message}"
  end

  def verification_queue
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    @pending_verification = InspectionJob.includes(inspection: :vehicle)
                                         .where(verification_status: 'pending')
                                         .where(assigned_mechanic_id: nil)
                                         .order(created_at: :desc)
                                         .limit(50)
    
    @recently_verified = InspectionJob.includes(inspection: :vehicle)
                                      .where(verification_status: ['verified', 'rejected', 'different'])
                                      .where('inspection_jobs.verified_at > ?', 24.hours.ago)
                                      .order(verified_at: :desc)
                                      .limit(30)
    
    @verified_today = InspectionJob.where(verification_status: ['verified', 'rejected', 'different'])
                                   .where('inspection_jobs.verified_at > ?', Time.current.beginning_of_day)
                                   .count
    
    @needs_action = InspectionJob.where(verification_status: 'pending').count
    @show_verification_link = @pending_verification.any?
  end

  def verify_job
    @job = InspectionJob.includes(inspection: :vehicle, parts_requests: [:part]).find(params[:id])
    
    if @job.assigned_mechanic_id.present? && @job.assigned_mechanic_id != current_user.id
      redirect_to vmcott_mechanic_dashboard_path, alert: "This job is already assigned to another mechanic."
      return
    end
    
    @job.update(assigned_mechanic_id: current_user.id) if @job.assigned_mechanic_id.nil?
    
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
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
              status: 'pending_approval',
              in_stock: true
            )
          else
            PartsRequest.create!(
              inspection: @job.inspection,
              inspection_job: @job,
              part: part,
              quantity: job_part.quantity,
              status: 'pending_approval',
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
                status: 'pending_approval',
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
                  status: 'pending_approval',
                  in_stock: true
                )
              else
                PartsRequest.create!(
                  inspection: @job.inspection,
                  inspection_job: corrected_job,
                  part: part,
                  quantity: part_data[:quantity],
                  status: 'pending_approval',
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
        if inspection.inspection_jobs.joins(:parts_requests).where(parts_requests: { status: 'pending_approval' }).any?
          inspection.update!(status: 'parts_coordinator_review')
          notify_inventory_manager(inspection)
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
    
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    unless @inspection.approved_for_repair?
      redirect_to vmcott_mechanic_dashboard_path, alert: "Can only report additional findings on approved work."
      return
    end
    
    @job = @inspection.inspection_jobs.new
  end

  def create_additional_finding
    @inspection = Inspection.find(params[:inspection_id])
    @job = InspectionJob.find_by(inspection_id: @inspection.id)
    
    additional_maintenance = @inspection.vehicle.maintenances.create!(
      service_type: "Additional Finding",
      description: params[:description],
      status: "Pending",
      assignment_type: "stores",
      date: Time.current,
      start_date: Time.current,
      end_date: 7.days.from_now,
      notes: "Additional finding during repair of inspection ##{@inspection.id}",
      additional_work: true,
      urgency: :high
    )
    
    notify_finance_for_additional_quotation(additional_maintenance)
    
    if @job.present?
      redirect_to vmcott_mechanic_job_path(@job), notice: "Additional finding logged. Finance will create a new quotation."
    else
      redirect_to vmcott_mechanic_dashboard_path, notice: "Additional finding logged. Finance will create a new quotation."
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Validation error in create_additional_finding: #{e.message}"
    
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

  # =====================================================
  # TASK MANAGEMENT METHODS
  # =====================================================
  
  def tasks
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    @assigned_tasks = JobTask
      .where(assigned_mechanic_id: current_user.id)
      .where(status: ['approved', 'in_progress', 'paused', 'blocked'])
      .includes(inspection_job: { inspection: :vehicle })
      .order(priority: :desc, created_at: :asc)
    
    @available_tasks = JobTask
      .where(assigned_mechanic_id: nil)
      .where(status: 'approved')
      .includes(inspection_job: { inspection: :vehicle })
      .order(priority: :desc, created_at: :asc)
      .limit(20)
    
    @completed_tasks_count = JobTask
      .where(assigned_mechanic_id: current_user.id)
      .where(status: 'completed')
      .where('completed_at >= ?', Time.current.beginning_of_day)
      .count
    
    @in_progress_count = @assigned_tasks.where(status: 'in_progress').count
    @paused_count = @assigned_tasks.where(status: 'paused').count
    @blocked_count = @assigned_tasks.where(status: 'blocked').count
    
    @total_hours_today = WorkSession
      .where(mechanic_id: current_user.id)
      .where(session_type: 'work')
      .where('started_at >= ?', Time.current.beginning_of_day)
      .sum(:duration_hours)
    
    render :tasks
  end

  def task_show
    @task = JobTask.find(params[:id])
    
    unless @task.assigned_mechanic_id == current_user.id
      redirect_to vmcott_mechanic_tasks_path, alert: "Access denied - this task is not assigned to you"
      return
    end
    
    @work_sessions = @task.work_sessions.order(started_at: :desc)
    @active_session = @task.active_work_session
    @dependencies = @task.depends_on
    @dependent_tasks = @task.dependent_jobs
    @inspection_job = @task.inspection_job
    @work_order = @inspection_job.work_order
  end

  def task_start
    @task = JobTask.find(params[:id])
    
    unless @task.assigned_mechanic_id == current_user.id
      redirect_to vmcott_mechanic_tasks_path, alert: "Access denied"
      return
    end
    
    service = TaskExecutionService.new(@task, current_user)
    idempotency_key = generate_idempotency_key
    
    if service.start(idempotency_key)
      redirect_to vmcott_mechanic_task_path(@task), notice: "Task started successfully"
    else
      redirect_to vmcott_mechanic_tasks_path, alert: service.errors.join(", ")
    end
  end

  def task_pause
    @task = JobTask.find(params[:id])
    reason = params[:reason] || params[:task][:reason] if params[:task]
    
    service = TaskExecutionService.new(@task, current_user)
    idempotency_key = generate_idempotency_key
    
    if service.pause(reason, idempotency_key)
      redirect_to vmcott_mechanic_task_path(@task), notice: "Task paused"
    else
      redirect_to vmcott_mechanic_task_path(@task), alert: service.errors.join(", ")
    end
  end

  def task_resume
    @task = JobTask.find(params[:id])
    
    service = TaskExecutionService.new(@task, current_user)
    idempotency_key = generate_idempotency_key
    
    if service.resume(idempotency_key)
      redirect_to vmcott_mechanic_task_path(@task), notice: "Task resumed"
    else
      redirect_to vmcott_mechanic_task_path(@task), alert: service.errors.join(", ")
    end
  end

  def task_complete
    @task = JobTask.find(params[:id])
    
    service = TaskExecutionService.new(@task, current_user)
    idempotency_key = generate_idempotency_key
    
    if service.complete(idempotency_key)
      redirect_to vmcott_mechanic_tasks_path, notice: "Task completed!"
    else
      redirect_to vmcott_mechanic_task_path(@task), alert: service.errors.join(", ")
    end
  end

  def task_block
    @task = JobTask.find(params[:id])
    reason = params[:reason] || params[:task][:reason] if params[:task]
    
    service = TaskExecutionService.new(@task, current_user)
    idempotency_key = generate_idempotency_key
    
    if service.block(reason, idempotency_key)
      redirect_to vmcott_mechanic_task_path(@task), notice: "Task blocked. Supervisor notified."
    else
      redirect_to vmcott_mechanic_task_path(@task), alert: service.errors.join(", ")
    end
  end

  def task_add_finding
    @task = JobTask.find(params[:task_id] || params[:id])
    
    finding = @task.findings.build(
      work_order: @task.inspection_job.work_order,
      description: params[:description],
      severity: params[:severity] || 'normal',
      blocking: params[:blocking] == 'true',
      finding_type: 'mechanic',
      created_by: current_user
    )
    
    if finding.save
      if finding.blocking?
        service = TaskExecutionService.new(@task, current_user)
        service.block(finding.description, generate_idempotency_key)
      end
      redirect_to vmcott_mechanic_task_path(@task), notice: "Finding added successfully"
    else
      redirect_to vmcott_mechanic_task_path(@task), alert: finding.errors.full_messages.join(", ")
    end
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

  def ensure_can_start_job
    return unless @job
    
    unless @job.status == 'approved_for_work'
      redirect_to vmcott_mechanic_job_path(@job), alert: "This job is not approved for work yet. Complete pre-check first."
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

  def ensure_can_do_pre_check
    return unless @job
    
    unless @job.status == 'assigned'
      redirect_to vmcott_mechanic_job_path(@job), alert: "This job is not ready for pre-check."
      return false
    end
    true
  end

  def generate_idempotency_key
    "task_#{params[:id]}_#{Time.current.to_i}_#{SecureRandom.hex(4)}"
  end

  def notify_inventory_manager(inspection, part_name = nil, quantity = nil, is_custom = false)
    inventory_manager_ids = User.where(role: 'inventory_manager').pluck(:id)
    
    if inventory_manager_ids.any?
      if part_name
        title = "New Part Request"
        message = "Part: #{part_name} x#{quantity} requested for #{inspection.vehicle.license_plate}"
      else
        title = "Parts Need Review"
        message = "Inspection ##{inspection.id} for #{inspection.vehicle.license_plate} has parts pending review."
      end
      
      Notification.create!(
        title: title,
        message: message,
        link: "/vmcott/inventory_manager/dashboard",
        user_id: inventory_manager_ids,
        notifiable_type: 'Inspection',
        notifiable_id: inspection.id
      )
    end
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

  def disable_caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end

  helper_method :job_status, :job_status_color, :waiting_status, :waiting_status_color

  def job_status(job, assignment = nil)
    if job.completed_at
      return "✅ Completed"
    end
    
    if assignment&.started_at
      return "🔧 In Progress"
    end
    
    case job.status
    when 'assigned'
      return "🔍 Pre-Check Required"
    when 'pre_check_in_progress'
      return "🔎 Pre-Check in Progress"
    when 'pre_check_completed'
      return "📋 Awaiting Approval"
    when 'approved_for_work'
      return "✅ Ready to Start"
    when 'in_progress'
      return "⚙️ In Progress"
    when 'paused'
      return "⏸️ Paused"
    when 'blocked'
      return "🚫 Blocked"
    else
      waiting_status(job)
    end
  end

  def job_status_color(job, assignment = nil)
    if job.completed_at
      return 'success'
    end
    
    if assignment&.started_at
      return 'warning'
    end
    
    case job.status
    when 'assigned'
      return 'info'
    when 'pre_check_in_progress'
      return 'primary'
    when 'pre_check_completed'
      return 'warning'
    when 'approved_for_work'
      return 'success'
    when 'in_progress'
      return 'info'
    when 'paused'
      return 'secondary'
    when 'blocked'
      return 'danger'
    else
      waiting_status_color(job)
    end
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