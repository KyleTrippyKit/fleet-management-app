# app/controllers/vmcott/mechanic/dashboard_controller.rb
class Vmcott::Mechanic::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_mechanic

  def index
    @assigned_jobs = MechanicAssignment.includes(:inspection_job => { :inspection => :vehicle })
                                       .where(mechanic_id: current_user.id, status: ['assigned', 'in_progress'])
                                       .order(created_at: :asc)

    @available_jobs = InspectionJob.includes(:inspection => :vehicle)
                                   .where(assigned_mechanic_id: nil, completed_at: nil)
                                   .where('requires_part_approval = false OR parts_approved = true')
                                   .order(created_at: :asc)

    # Group available jobs by vehicle for display
    @jobs_by_vehicle = @available_jobs.group_by { |job| job.inspection.vehicle }

    @completed_today = MechanicAssignment.where(mechanic_id: current_user.id)
                                         .where('completed_at >= ?', Date.current.beginning_of_day)
                                         .count

    @waiting_parts = MechanicAssignment.where(mechanic_id: current_user.id, status: 'waiting_parts')
                                       .includes(:inspection_job)
  end

  def show_job
    @assignment = MechanicAssignment.find(params[:id])
    @job = @assignment.inspection_job
    @inspection = @job.inspection
    @vehicle = @inspection.vehicle
    @parts = @job.inspection_job_parts.includes(:part)
  end

  def assign_self
    job = InspectionJob.find(params[:id])
    if job.update(assigned_mechanic_id: current_user.id)
      job.mechanic_assignments.create!(mechanic: current_user, status: 'assigned')
      redirect_to vmcott_mechanic_dashboard_path, notice: "Job assigned to you."
    else
      redirect_to vmcott_mechanic_dashboard_path, alert: "Could not assign job."
    end
  end

  def start_job
    assignment = MechanicAssignment.find(params[:id])
    assignment.update!(status: 'in_progress', started_at: Time.current)
    redirect_to vmcott_mechanic_job_path(assignment), notice: "Job started."
  end

  def update_progress
    assignment = MechanicAssignment.find(params[:id])
    if params[:progress_update].present?
      assignment.update(mechanic_notes: "#{assignment.mechanic_notes}\n[#{Time.current.strftime('%H:%M')}] #{params[:progress_update]}")
      flash[:notice] = "Progress updated."
    else
      flash[:alert] = "Progress note cannot be blank."
    end
    redirect_to vmcott_mechanic_job_path(assignment)
  end

  def log_parts_used
    assignment = MechanicAssignment.find(params[:id])
    part = Part.find(params[:part_id])
    qty = params[:quantity].to_i

    if part.current_stock >= qty
      part.update!(current_stock: part.current_stock - qty)
      # Log in assignment notes
      assignment.update(mechanic_notes: "#{assignment.mechanic_notes}\n[PARTS] Used #{qty}x #{part.name}")
      render json: { success: true, new_stock: part.current_stock }
    else
      render json: { success: false, message: "Insufficient stock" }, status: :unprocessable_entity
    end
  end

  def request_qc
    assignment = MechanicAssignment.find(params[:id])
    assignment.update!(status: 'completed', completed_at: Time.current)
    # Create a QC assignment if needed
    job = assignment.inspection_job
    job.update(completed_at: Time.current)

    # If all jobs for this inspection are done, mark inspection ready for QC
    inspection = job.inspection
    if inspection.inspection_jobs.where(completed_at: nil).none?
      inspection.update!(status: 'ready_for_qc')
      # Notify inspector
      Notification.create!(
        title: "QC Required",
        message: "All jobs for #{inspection.vehicle.license_plate} are completed. Please perform final QC.",
        user: User.inspectors.first, # or assign to specific inspector
        notifiable: inspection
      )
    end

    redirect_to vmcott_mechanic_dashboard_path, notice: "Job completed and QC requested."
  end

  private

  def require_mechanic
    unless current_user.mechanic? || current_user.maintenance_supervisor? || current_user.admin?
      redirect_to root_path, alert: "Access denied"
    end
  end
end