# app/controllers/vmcott/mechanic/dashboard_controller.rb
class Vmcott::Mechanic::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_mechanic
  before_action :set_job_context, only: [:show_job, :start_job, :update_progress, :log_parts_used, :request_qc]

  def index
    @assigned_jobs = MechanicAssignment.includes(inspection_job: { inspection: :vehicle })
                                       .where(mechanic_id: current_user.id, status: ['assigned', 'in_progress'])
                                       .order(created_at: :asc)

    @available_jobs = InspectionJob.includes(inspection: :vehicle)
                                   .where(assigned_mechanic_id: nil, completed_at: nil)
                                   .where('requires_part_approval = false OR parts_approved = true')
                                   .order(created_at: :asc)

    # Group assigned jobs by vehicle for display
    @jobs_by_vehicle = @assigned_jobs.map(&:inspection_job).compact.group_by { |job| job.inspection&.vehicle }

    @completed_today = MechanicAssignment.where(mechanic_id: current_user.id)
                                         .where('completed_at >= ?', Date.current.beginning_of_day)
                                         .count

    @waiting_parts = MechanicAssignment.where(mechanic_id: current_user.id, status: 'waiting_parts')
                                       .includes(:inspection_job)
    
    # Fix: Use inspection status instead of job status
    @pending_qc = Inspection.joins(inspection_jobs: :mechanic_assignments)
                            .where(mechanic_assignments: { mechanic_id: current_user.id })
                            .where(status: 'ready_for_qc')
                            .distinct
                            .count
                           
    @recently_completed = InspectionJob.where(assigned_mechanic_id: current_user.id)
                                       .where.not(completed_at: nil)
                                       .order(completed_at: :desc)
                                       .limit(10)
    
    # Jobs taken by other mechanics
    @taken_jobs = InspectionJob.includes(inspection: :vehicle)
                               .where.not(assigned_mechanic_id: nil)
                               .where.not(assigned_mechanic_id: current_user.id)
                               .where(completed_at: nil)
                               .order(created_at: :desc)
                               .limit(20)
  rescue => e
    Rails.logger.error "Error in mechanic dashboard index: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    flash[:alert] = "An error occurred while loading the dashboard: #{e.message}"
    @assigned_jobs = []
    @available_jobs = []
    @jobs_by_vehicle = {}
    @completed_today = 0
    @waiting_parts = []
    @pending_qc = 0
    @recently_completed = []
    @taken_jobs = []
  end

  def show_job
    # @job and @assignment are set by set_job_context
    @inspection = @job&.inspection
    @vehicle = @inspection&.vehicle
    @parts = @job&.inspection_job_parts&.includes(:part) || []
    
    # If any required data is missing, show appropriate error
    if @job.nil?
      flash[:alert] = "Job not found."
      redirect_to vmcott_mechanic_dashboard_path and return
    end
    
    if @inspection.nil?
      flash[:alert] = "Inspection details not found for this job."
      redirect_to vmcott_mechanic_dashboard_path and return
    end
    
    render 'vmcott/mechanic/dashboard/show_job'
  rescue => e
    Rails.logger.error "Error in show_job: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    flash[:alert] = "An error occurred while loading the job details: #{e.message}"
    redirect_to vmcott_mechanic_dashboard_path
  end

  def assign_self
    job = InspectionJob.find_by(id: params[:id])
    
    if job.nil?
      redirect_to vmcott_mechanic_dashboard_path, alert: "Job not found."
      return
    end
    
    if job.assigned_mechanic_id.present? && job.assigned_mechanic_id != current_user.id
      assigned_mechanic = User.find_by(id: job.assigned_mechanic_id)
      redirect_to vmcott_mechanic_dashboard_path, alert: "This job is already assigned to #{assigned_mechanic&.name || 'another mechanic'}."
      return
    end
    
    # Assign job to current user
    job.update!(assigned_mechanic_id: current_user.id)
    
    # Create or update assignment
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

  def start_job
    if @job.assigned_mechanic_id != current_user.id
      redirect_to vmcott_mechanic_dashboard_path, alert: "You cannot start a job that isn't assigned to you."
      return
    end
    
    # Find or create assignment
    assignment = MechanicAssignment.find_or_initialize_by(
      inspection_job_id: @job.id,
      mechanic_id: current_user.id
    )
    
    assignment.status = 'in_progress'
    assignment.started_at = Time.current
    assignment.save!
    
    # Note: Job doesn't have a status field, so we don't update it
    # The job's progress is tracked through the assignment
    
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

  def log_parts_used
    if @job.assigned_mechanic_id != current_user.id
      render json: { success: false, message: "You cannot log parts for a job that isn't assigned to you." }, status: :unauthorized
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

    # Update stock
    part.update!(current_stock: part.current_stock - qty)
    
    # Log in assignment notes
    assignment = MechanicAssignment.find_by(inspection_job_id: @job.id, mechanic_id: current_user.id)
    if assignment
      assignment.update(
        mechanic_notes: "#{assignment.mechanic_notes}\n[PARTS] Used #{qty}x #{part.name} (Stock left: #{part.current_stock})"
      )
    end
    
    # Create part usage record if needed
    InspectionJobPart.find_or_create_by!(
      inspection_job_id: @job.id,
      part_id: part.id
    ) do |jp|
      jp.quantity = qty
      jp.notes = "Used by mechanic #{current_user.name}"
    end

    render json: { success: true, new_stock: part.current_stock, message: "#{qty}x #{part.name} logged successfully" }
  rescue => e
    Rails.logger.error "Error in log_parts_used: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: { success: false, message: "An error occurred: #{e.message}" }, status: :internal_server_error
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
    
    # Update assignment
    assignment = MechanicAssignment.find_by(inspection_job_id: @job.id, mechanic_id: current_user.id)
    if assignment
      assignment.update!(
        status: 'completed', 
        completed_at: Time.current
      )
    end
    
    # Update job completed_at
    @job.update!(
      completed_at: Time.current
    )

    # Check if all jobs for this inspection are done
    if inspection.inspection_jobs.where(completed_at: nil).none?
      inspection.update!(status: 'ready_for_pickup')  # Using ready_for_pickup instead of ready_for_qc
      
      # Notify inspectors
      if defined?(Notification)
        User.where(role: ['inspector', 'admin']).each do |inspector|
          Notification.create!(
            user: inspector,
            title: "QC Required for #{inspection.vehicle&.license_plate || 'Vehicle'}",
            message: "All jobs for inspection ##{inspection.id} are completed. Please perform final QC.",
            notifiable: inspection,
            link: vmcott_inspector_qc_path(inspection)
          ) rescue nil
        end
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
    # Try to find by InspectionJob ID
    @job = InspectionJob.includes(inspection: :vehicle).find_by(id: params[:id])
    
    if @job.nil?
      flash[:alert] = "Job not found."
      redirect_to vmcott_mechanic_dashboard_path and return false
    end
    
    # Find or create assignment for current user if job is assigned to them
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
end