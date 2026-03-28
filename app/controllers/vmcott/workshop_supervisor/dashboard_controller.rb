class Vmcott::WorkshopSupervisor::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_workshop_supervisor
  before_action :set_stats, only: [:index]
  
  # Disable caching
  before_action :disable_caching
  before_action :disable_turbo_cache

  def index
    # ========================================
    # PENDING TASKS (Need Approval)
    # ========================================
    @pending_tasks = JobTask
      .where(status: 'pending')
      .includes(inspection_job: { inspection: :vehicle })
      .order(created_at: :asc)
      .limit(50)
    
    # ========================================
    # BLOCKED TASKS (Need Unblocking)
    # ========================================
    @blocked_tasks = JobTask
      .where(status: 'blocked')
      .includes(inspection_job: { inspection: :vehicle })
      .order(blocked_at: :desc)
      .limit(50)
    
    # ========================================
    # PENDING WORK ORDERS (Need Approval)
    # ========================================
    @pending_work_orders = WorkOrder
      .where(status: 'awaiting_approval')
      .includes(:vehicle)
      .order(created_at: :asc)
      .limit(20)
    
    # ========================================
    # ACTIVE JOBS (In Progress)
    # ========================================
    @active_jobs = InspectionJob
      .where(status: 'in_progress')
      .includes(inspection: :vehicle, job_tasks: :work_sessions)
      .order(started_at: :desc)
      .limit(20)
    
    # ========================================
    # 🔥 NEW: PRE-CHECK COMPLETED JOBS (Need Review)
    # ========================================
    @pre_check_completed = InspectionJob
      .where(status: 'pre_check_completed')
      .includes(inspection: :vehicle, assigned_mechanic: {})
      .order(pre_check_completed_at: :desc)
      .limit(30)
    
    # ========================================
    # 🔥 NEW: PENDING PARTS REQUESTS (Need Approval)
    # ========================================
    @pending_parts_requests = PartsRequest
      .where(status: 'pending_approval')
      .includes(:inspection, :part, :inspection_job)
      .order(created_at: :desc)
      .limit(30)
    
    # ========================================
    # PENDING FINDINGS (Need Review)
    # ========================================
    @pending_findings = Finding
      .where(status: 'pending')
      .where(blocking: true)
      .includes(:work_order, :created_by)
      .order(created_at: :desc)
      .limit(20)
    
    # ========================================
    # STATS
    # ========================================
    @pre_check_count = @pre_check_completed.count
    @pending_parts_count = @pending_parts_requests.count
  end

  # =====================================================
  # PRE-CHECK REVIEW METHODS
  # =====================================================
  
  def review_pre_check
    @job = InspectionJob.find(params[:id])
    @additional_findings = @job.additional_findings
    @mechanic = @job.assigned_mechanic
    
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end
  
  def approve_pre_check
    @job = InspectionJob.find(params[:id])
    
    ActiveRecord::Base.transaction do
      # Approve the job for work
      @job.update!(
        status: 'approved_for_work',
        approved_at: Time.current,
        supervisor_id: current_user.id
      )
      
      # Create additional jobs from findings if approved
      if params[:approved_findings].present?
        params[:approved_findings].each do |finding_index, finding_data|
          if finding_data[:approved] == 'true'
            additional_job = @job.inspection.inspection_jobs.create!(
              description: finding_data[:description],
              priority: finding_data[:severity] == 'critical' ? 'high' : 'normal',
              estimated_hours: finding_data[:estimated_hours],
              status: 'approved_for_work',
              recommendation_source: 'mechanic_pre_check',
              parent_job_id: @job.id,
              assigned_mechanic_id: @job.assigned_mechanic_id
            )
            
            # Notify mechanic
            Notification.create!(
              user: @job.assigned_mechanic,
              title: "Additional Work Approved",
              message: "Additional job '#{finding_data[:description]}' has been approved for work.",
              link: "/vmcott/mechanic/jobs/#{additional_job.id}",
              notification_type: 'success',
              notifiable: additional_job
            )
          end
        end
      end
      
      # Notify mechanic that pre-check is approved
      Notification.create!(
        user: @job.assigned_mechanic,
        title: "Pre-Check Approved",
        message: "Your pre-check for job ##{@job.id} has been approved. You can now start work.",
        link: "/vmcott/mechanic/jobs/#{@job.id}",
        notification_type: 'success',
        notifiable: @job
      )
      
      flash[:notice] = "✅ Pre-check approved. Job is ready for work."
    end
    
    redirect_to vmcott_workshop_supervisor_dashboard_path
  rescue => e
    Rails.logger.error "Error approving pre-check: #{e.message}"
    flash[:alert] = "Error approving pre-check: #{e.message}"
    redirect_to vmcott_workshop_supervisor_review_pre_check_path(@job)
  end
  
  def reject_pre_check
    @job = InspectionJob.find(params[:id])
    reason = params[:rejection_reason] || "Additional work not approved at this time"
    
    ActiveRecord::Base.transaction do
      @job.update!(
        status: 'assigned',
        blocked_reason: reason
      )
      
      # Notify mechanic
      Notification.create!(
        user: @job.assigned_mechanic,
        title: "Pre-Check Findings Rejected",
        message: "Your pre-check findings for job ##{@job.id} were not approved. Reason: #{reason}",
        link: "/vmcott/mechanic/jobs/#{@job.id}",
        notification_type: 'warning',
        notifiable: @job
      )
      
      flash[:alert] = "❌ Pre-check findings rejected. Job returned to mechanic."
    end
    
    redirect_to vmcott_workshop_supervisor_dashboard_path
  end

  # =====================================================
  # PARTS REQUEST APPROVAL METHODS
  # =====================================================
  
  def review_parts_request
    @parts_request = PartsRequest.find(params[:id])
    @job = @parts_request.inspection_job
    @vehicle = @parts_request.inspection.vehicle
    
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end
  
  def approve_parts_request
    @parts_request = PartsRequest.find(params[:id])
    
    @parts_request.approve!(current_user)
    
    flash[:notice] = "✅ Parts request approved. Inventory manager will issue the parts."
    redirect_to vmcott_workshop_supervisor_dashboard_path
  rescue => e
    Rails.logger.error "Error approving parts request: #{e.message}"
    flash[:alert] = "Error approving parts request: #{e.message}"
    redirect_to vmcott_workshop_supervisor_review_parts_request_path(@parts_request)
  end
  
  def reject_parts_request
    @parts_request = PartsRequest.find(params[:id])
    reason = params[:rejection_reason] || "Not approved at this time"
    
    @parts_request.reject!(current_user, reason)
    
    flash[:alert] = "❌ Parts request rejected: #{reason}"
    redirect_to vmcott_workshop_supervisor_dashboard_path
  rescue => e
    Rails.logger.error "Error rejecting parts request: #{e.message}"
    flash[:alert] = "Error rejecting parts request: #{e.message}"
    redirect_to vmcott_workshop_supervisor_review_parts_request_path(@parts_request)
  end

  # =====================================================
  # EXISTING METHODS (tasks, work_orders, findings, etc.)
  # =====================================================
  
  def tasks
    @tasks = JobTask
      .includes(inspection_job: { inspection: :vehicle })
      .order(created_at: :desc)
      .page(params[:page])
      .per(20)
    
    @status_filter = params[:status]
    @tasks = @tasks.where(status: @status_filter) if @status_filter.present?
  end

  def task_show
    @task = JobTask.find(params[:id])
    @work_sessions = @task.work_sessions.order(started_at: :desc)
    @dependencies = @task.depends_on
    
    # Safe navigation to handle nil inspection_job
    @inspection_job = @task.inspection_job
    @work_order = @inspection_job&.work_order if @inspection_job.present?
    @mechanic = @task.assigned_mechanic
    
    # Add debug logging if needed
    unless @inspection_job
      Rails.logger.warn "Task #{@task.id} has no inspection_job associated"
    end
    
    unless @work_order
      Rails.logger.warn "Task #{@task.id} has no work_order (inspection_job_id: #{@inspection_job&.id})"
    end
  end

  def task_approve
    @task = JobTask.find(params[:id])
    
    if @task.status == 'pending'
      @task.transition_to!('approved', current_user, request.remote_ip)
      
      if @task.assigned_mechanic
        Notification.create!(
          user: @task.assigned_mechanic,
          title: "Task Approved",
          message: "Task '#{@task.name}' has been approved. You can start working.",
          link: "/vmcott/mechanic/tasks/#{@task.id}",
          notification_type: 'success',
          notifiable: @task
        )
      end
      
      flash[:notice] = "Task approved successfully."
    else
      flash[:alert] = "Task cannot be approved in its current state."
    end
    
    redirect_to vmcott_workshop_supervisor_task_path(@task)
  end

  def task_reject
    @task = JobTask.find(params[:id])
    reason = params[:reason] || "Task rejected by supervisor"
    
    if @task.status == 'pending'
      @task.transition_to!('skipped', current_user, request.remote_ip)
      @task.update!(blocked_reason: reason)
      
      Notification.create!(
        user: @task.inspection_job.created_by,
        title: "Task Rejected",
        message: "Task '#{@task.name}' was rejected. Reason: #{reason}",
        link: "/vmcott/workshop_supervisor/tasks/#{@task.id}",
        notification_type: 'error',
        notifiable: @task
      )
      
      flash[:notice] = "Task rejected."
    else
      flash[:alert] = "Task cannot be rejected."
    end
    
    redirect_to vmcott_workshop_supervisor_task_path(@task)
  end

  def task_unblock
    @task = JobTask.find(params[:id])
    
    if @task.status == 'blocked'
      service = TaskExecutionService.new(@task, current_user)
      idempotency_key = "unblock_#{@task.id}_#{Time.current.to_i}"
      
      if service.unblock(idempotency_key)
        flash[:notice] = "Task unblocked successfully."
      else
        flash[:alert] = service.errors.join(", ")
      end
    else
      flash[:alert] = "Task is not blocked."
    end
    
    redirect_to vmcott_workshop_supervisor_task_path(@task)
  end

  def task_assign_mechanic
    @task = JobTask.find(params[:id])
    mechanic_id = params[:mechanic_id]
    
    if @task.status == 'approved' && mechanic_id.present?
      mechanic = User.find(mechanic_id)
      
      @task.update!(
        assigned_mechanic: mechanic,
        assigned_at: Time.current
      )
      
      Notification.create!(
        user: mechanic,
        title: "Task Assigned",
        message: "Task '#{@task.name}' has been assigned to you.",
        link: "/vmcott/mechanic/tasks/#{@task.id}",
        notification_type: 'info',
        notifiable: @task
      )
      
      flash[:notice] = "Task assigned to #{mechanic.name}."
    else
      flash[:alert] = "Could not assign task."
    end
    
    redirect_to vmcott_workshop_supervisor_task_path(@task)
  end

  def work_orders
    @work_orders = WorkOrder
      .includes(:vehicle, :customer)
      .order(created_at: :desc)
      .page(params[:page])
      .per(20)
    
    @status_filter = params[:status]
    @work_orders = @work_orders.where(status: @status_filter) if @status_filter.present?
  end

  def work_order_show
    @work_order = WorkOrder.find(params[:id])
    @inspections = @work_order.inspections
    @jobs = @work_order.inspection_jobs
    @tasks = @work_order.job_tasks
    @findings = @work_order.findings
    @timeline = @work_order.timeline_events
  end

  def work_order_approve
    @work_order = WorkOrder.find(params[:id])
    service = WorkOrderService.new(@work_order, current_user)
    
    if service.transition_to('approved')
      flash[:notice] = "Work order approved."
    else
      flash[:alert] = service.errors.join(", ")
    end
    
    redirect_to vmcott_workshop_supervisor_work_order_path(@work_order)
  end

  def work_order_hold
    @work_order = WorkOrder.find(params[:id])
    service = WorkOrderService.new(@work_order, current_user)
    reason = params[:reason] || "Placed on hold by supervisor"
    
    if service.transition_to('on_hold')
      @work_order.update!(hold_reason: reason)
      flash[:notice] = "Work order placed on hold."
    else
      flash[:alert] = service.errors.join(", ")
    end
    
    redirect_to vmcott_workshop_supervisor_work_order_path(@work_order)
  end

  def findings
    @findings = Finding
      .includes(:work_order, :created_by)
      .order(created_at: :desc)
      .paginate(page: params[:page], per_page: 20)
    
    @status_filter = params[:status]
    @findings = @findings.where(status: @status_filter) if @status_filter.present?
  end

  def finding_show
    @finding = Finding.find(params[:id])
    @work_order = @finding.work_order
    @tasks = @work_order.job_tasks
  end

  def finding_approve
    @finding = Finding.find(params[:id])
    
    if @finding.status == 'pending'
      @finding.update!(
        status: 'approved',
        approved_by: current_user,
        approved_at: Time.current
      )
      
      if params[:create_task] == 'true'
        task = @finding.work_order.job_tasks.create!(
          inspection_job: @finding.inspection_job,
          name: @finding.description,
          description: @finding.description,
          status: 'approved',
          estimated_hours: params[:estimated_hours],
          priority: @finding.severity == 'critical' ? 'high' : 'normal'
        )
        
        flash[:notice] = "Finding approved and task created."
      else
        flash[:notice] = "Finding approved."
      end
      
      Notification.create!(
        user: @finding.created_by,
        title: "Finding Approved",
        message: "Your finding has been approved.",
        link: "/vmcott/workshop_supervisor/findings/#{@finding.id}",
        notification_type: 'success',
        notifiable: @finding
      )
    else
      flash[:alert] = "Finding cannot be approved."
    end
    
    redirect_to vmcott_workshop_supervisor_finding_path(@finding)
  end

  def finding_reject
    @finding = Finding.find(params[:id])
    reason = params[:reason] || "Finding rejected"
    
    if @finding.status == 'pending'
      @finding.update!(
        status: 'rejected',
        approved_by: current_user,
        approved_at: Time.current,
        notes: reason
      )
      
      flash[:notice] = "Finding rejected."
    else
      flash[:alert] = "Finding cannot be rejected."
    end
    
    redirect_to vmcott_workshop_supervisor_finding_path(@finding)
  end

  def mechanics
    # Use active scope if it exists, otherwise use where
    @mechanics = if User.respond_to?(:active)
      User.where(role: 'mechanic').active
    else
      User.where(role: 'mechanic')
    end
    
    @task_counts = JobTask.group(:assigned_mechanic_id).count
    @pre_check_counts = InspectionJob.where(status: 'pre_check_completed').group(:assigned_mechanic_id).count
    @completed_today = JobTask.where(status: 'completed')
                              .where('completed_at >= ?', Time.current.beginning_of_day)
                              .group(:assigned_mechanic_id)
                              .count
  end

  def reports
    @start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : 1.week.ago.to_date
    @end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : Date.current
    
    @tasks_completed = JobTask.where(status: 'completed')
                              .where(completed_at: @start_date.beginning_of_day..@end_date.end_of_day)
                              .count
    
    @total_hours = WorkSession.where(session_type: 'work')
                              .where(started_at: @start_date.beginning_of_day..@end_date.end_of_day)
                              .sum(:duration_hours)
    
    @tasks_by_mechanic = JobTask.where(status: 'completed')
                                .where(completed_at: @start_date.beginning_of_day..@end_date.end_of_day)
                                .group(:assigned_mechanic_id)
                                .count
    
    @hours_by_mechanic = WorkSession.where(session_type: 'work')
                                    .where(started_at: @start_date.beginning_of_day..@end_date.end_of_day)
                                    .group(:mechanic_id)
                                    .sum(:duration_hours)
    
    @work_orders_completed = WorkOrder.where(status: 'completed')
                                      .where(completed_at: @start_date.beginning_of_day..@end_date.end_of_day)
                                      .count
    
    @total_revenue = WorkOrder.where(status: 'completed')
                              .where(completed_at: @start_date.beginning_of_day..@end_date.end_of_day)
                              .sum(:total_amount)
    
    @parts_requests_approved = PartsRequest.where(status: 'approved')
                                           .where(approved_at: @start_date.beginning_of_day..@end_date.end_of_day)
                                           .count
    
    @pre_check_completed = InspectionJob.where(status: 'pre_check_completed')
                                        .where(pre_check_completed_at: @start_date.beginning_of_day..@end_date.end_of_day)
                                        .count
  end

  private

  def require_workshop_supervisor
    unless current_user.role == 'workshop_supervisor' || current_user.admin?
      redirect_to root_path, alert: "Access denied. Workshop Supervisor privileges required."
    end
  end

  def set_stats
    @stats = {
      pending_tasks: JobTask.where(status: 'pending').count,
      blocked_tasks: JobTask.where(status: 'blocked').count,
      pending_work_orders: WorkOrder.where(status: 'awaiting_approval').count,
      active_jobs: InspectionJob.where(status: 'in_progress').count,
      pending_findings: Finding.where(status: 'pending', blocking: true).count,
      active_mechanics: User.where(role: 'mechanic', is_active: true).count,
      pre_check_review: InspectionJob.where(status: 'pre_check_completed').count,
      pending_parts_requests: PartsRequest.where(status: 'pending_approval').count
    }
  end

  def disable_caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end

  def disable_turbo_cache
    response.headers["Turbo-Visit-Control"] = "reload"
    response.headers["Turbo-Cache-Control"] = "no-cache"
  end
end