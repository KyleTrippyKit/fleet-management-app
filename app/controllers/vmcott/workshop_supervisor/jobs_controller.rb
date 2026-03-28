# app/controllers/vmcott/workshop_supervisor/jobs_controller.rb
class Vmcott::WorkshopSupervisor::JobsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_supervisor
  before_action :set_inspection, only: [:review, :update_jobs, :approve, :reject]
  
  def review
    @inspection = Inspection.includes(
      :vehicle,
      :inspector,
      inspection_jobs: []
    ).find(params[:inspection_id])
    
    @pending_approval = @inspection.inspection_jobs.where(status: 'pending_supervisor_review')
    @mechanics = User.where(role: 'mechanic').active
  end
  
  def update_jobs
    # Update existing jobs (edit descriptions, costs, etc.)
    if params[:jobs].present?
      params[:jobs].each do |job_id, job_params|
        job = @inspection.inspection_jobs.find(job_id)
        job.update!(
          description: job_params[:description],
          estimated_labor_cost: job_params[:estimated_labor_cost],
          priority: job_params[:priority],
          assigned_mechanic_id: job_params[:assigned_mechanic_id]
        )
      end
    end
    
    # Add new jobs
    if params[:new_jobs].present?
      params[:new_jobs].each do |new_job|
        @inspection.inspection_jobs.create!(
          description: new_job[:description],
          estimated_labor_cost: new_job[:estimated_labor_cost],
          priority: new_job[:priority] || 'normal',
          assigned_mechanic_id: new_job[:assigned_mechanic_id],
          status: 'pending_mechanic_review'
        )
      end
    end
    
    # Remove jobs
    if params[:remove_job_ids].present?
      @inspection.inspection_jobs.where(id: params[:remove_job_ids]).destroy_all
    end
    
    redirect_to review_workshop_supervisor_inspection_path(@inspection), 
                notice: "Jobs updated successfully"
  end
  
  def approve
    # Mark inspection as approved for repair
    @inspection.update!(
      status: :approved_for_repair,
      approved_at: Time.current,
      supervisor_id: current_user.id
    )
    
    # Update all jobs to approved status
    @inspection.inspection_jobs.update_all(
      status: 'pending_mechanic_work',
      verification_status: 'approved'
    )
    
    # Notify mechanics
    notify_mechanics(@inspection)
    
    redirect_to workshop_supervisor_dashboard_path, 
                notice: "Inspection approved and jobs assigned to mechanics"
  end
  
  def reject
    reason = params[:rejection_reason] || "Jobs need revision"
    
    @inspection.update!(
      status: :pending_inspection,
      rejection_reason: reason
    )
    
    # Notify inspector
    Notification.create!(
      user: @inspection.inspector,
      title: "Job Recommendations Rejected",
      message: "Your job recommendations for #{@inspection.vehicle.license_plate} need revision: #{reason}",
      link: vmcott_inspector_inspection_path(@inspection),
      notification_type: 'warning',
      notifiable: @inspection
    )
    
    redirect_to workshop_supervisor_dashboard_path, 
                alert: "Jobs rejected and sent back to inspector"
  end
  
  private
  
  def set_inspection
    @inspection = Inspection.find(params[:inspection_id])
  end
  
  def require_supervisor
    unless current_user.role == 'workshop_supervisor' || current_user.admin?
      redirect_to root_path, alert: "Access denied. Supervisor privileges required."
    end
  end
  
  def notify_mechanics(inspection)
    mechanic_ids = User.where(role: 'mechanic').pluck(:id)
    Notification.create!(
      user_id: mechanic_ids,
      title: "New Jobs Available!",
      message: "Work order for #{inspection.vehicle.license_plate} is ready. #{inspection.inspection_jobs.count} jobs available.",
      link: "/vmcott/mechanic/dashboard",
      notification_type: 'success',
      notifiable: inspection
    )
  end
end