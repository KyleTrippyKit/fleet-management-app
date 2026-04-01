# app/controllers/vmcott/workshop_supervisor/jobs_controller.rb
class Vmcott::WorkshopSupervisor::JobsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_supervisor
  before_action :set_inspection, only: [:update_jobs, :approve, :reject]
  
  def index
    @jobs = InspectionJob
      .includes(inspection: :vehicle)
      .order(created_at: :desc)
      .page(params[:page])
      .per(20)
    
    @status_filter = params[:status]
    @jobs = @jobs.where(status: @status_filter) if @status_filter.present?
  end

  def show
    @job = InspectionJob.find(params[:id])
    @tasks = @job.job_tasks
    @work_sessions = WorkSession.joins(:job_task)
                                .where(job_tasks: { inspection_job_id: @job.id })
    @parts_requests = @job.parts_requests
    @mechanic = @job.assigned_mechanic
    @inspection = @job.inspection
    @vehicle = @inspection&.vehicle
    
    # Add any other data needed for the show view
  end

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
    
    redirect_to review_vmcott_workshop_supervisor_inspection_path(@inspection),
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
    
    redirect_to vmcott_workshop_supervisor_dashboard_path, 
                notice: "Inspection approved and jobs assigned to mechanics"
  end
  
  def reject
    reason = params[:rejection_reason] || "Jobs need revision"
    
    @inspection.update!(
      status: :pending_inspection,
      rejection_reason: reason
    )
    
    # Notify inspector
    if @inspection.inspector.present?
      Notification.create!(
        user: @inspection.inspector,
        title: "Job Recommendations Rejected",
        message: "Your job recommendations for #{@inspection.vehicle&.license_plate || 'vehicle'} need revision: #{reason}",
        link: vmcott_inspector_inspection_path(@inspection),
        notification_type: 'warning',
        notifiable: @inspection
      )
    end
    
    redirect_to vmcott_workshop_supervisor_dashboard_path, 
                alert: "Jobs rejected and sent back to inspector"
  end

  def assign
    @job = InspectionJob.find(params[:id])
    mechanic_id = params[:mechanic_id]
    
    if mechanic_id.present?
      mechanic = User.find(mechanic_id)
      @job.update!(
        assigned_mechanic: mechanic,
        assigned_at: Time.current,
        status: 'assigned'
      )
      
      Notification.create!(
        user: mechanic,
        title: "New Job Assigned",
        message: "Job ##{@job.id} has been assigned to you.",
        link: vmcott_mechanic_job_path(@job),
        notification_type: 'info',
        notifiable: @job
      )
      
      flash[:notice] = "Job assigned to #{mechanic.name}"
    else
      flash[:alert] = "Please select a mechanic"
    end
    
    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def reassign
    @job = InspectionJob.find(params[:id])
    mechanic_id = params[:mechanic_id]
    
    if mechanic_id.present?
      mechanic = User.find(mechanic_id)
      
      # Notify old mechanic if there was one
      if @job.assigned_mechanic.present?
        Notification.create!(
          user: @job.assigned_mechanic,
          title: "Job Reassigned",
          message: "Job ##{@job.id} has been reassigned to another mechanic.",
          link: vmcott_mechanic_dashboard_path,
          notification_type: 'warning',
          notifiable: @job
        )
      end
      
      @job.update!(
        assigned_mechanic: mechanic,
        assigned_at: Time.current,
        reassigned_at: Time.current,
        status: 'assigned'
      )
      
      Notification.create!(
        user: mechanic,
        title: "Job Reassigned to You",
        message: "Job ##{@job.id} has been reassigned to you.",
        link: vmcott_mechanic_job_path(@job),
        notification_type: 'info',
        notifiable: @job
      )
      
      flash[:notice] = "Job reassigned to #{mechanic.name}"
    else
      flash[:alert] = "Please select a mechanic"
    end
    
    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def overdue
    @overdue_jobs = InspectionJob
      .where('estimated_completion_date < ?', Date.current)
      .where(completed_at: nil)
      .includes(inspection: :vehicle)
      .order(estimated_completion_date: :asc)
      .limit(50)
  end

  def stats
    @stats = {
      total_jobs: InspectionJob.count,
      completed_today: InspectionJob.where('completed_at >= ?', Time.current.beginning_of_day).count,
      in_progress: InspectionJob.where(status: 'in_progress').count,
      pending_approval: InspectionJob.where(status: 'pending_approval').count,
      blocked: InspectionJob.where(status: 'blocked').count,
      assigned: InspectionJob.where(status: 'assigned').count,
      average_completion_time: InspectionJob.where.not(completed_at: nil)
                                            .average("EXTRACT(EPOCH FROM (completed_at - created_at))/3600")
                                            .to_f
    }
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
    return unless mechanic_ids.any?
    
    Notification.create!(
      user_id: mechanic_ids,
      title: "New Jobs Available!",
      message: "Work order for #{inspection.vehicle&.license_plate || 'vehicle'} is ready. #{inspection.inspection_jobs.count} jobs available.",
      link: "/vmcott/mechanic/dashboard",
      notification_type: 'success',
      notifiable: inspection
    )
  end
end