# app/controllers/vmcott/workshop_supervisor/dashboard_controller.rb
class Vmcott::WorkshopSupervisor::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_workshop_supervisor
  before_action :set_stats, only: [:index]
  
  # CRITICAL: Disable ALL caching for this controller to prevent white screen issues
  before_action :disable_all_caching

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
    # PRE-CHECK COMPLETED JOBS (Need Review)
    # ========================================
    @pre_check_completed = InspectionJob
      .where(status: 'pre_check_completed')
      .includes(inspection: :vehicle, assigned_mechanic: {})
      .order(pre_check_completed_at: :desc)
      .limit(30)
    
    # ========================================
    # PENDING PARTS REQUESTS (Need Approval)
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
    
    # ========================================
    # WORKFLOW SELECTION PENDING (NEW)
    # ========================================
    @workflow_pending = Inspection
      .where(status: 'pending_procurement_quotation')
      .where(workflow_selected_by_id: nil)
      .includes(:vehicle, :inspection_jobs, :parts_requests)
      .order(created_at: :asc)
      .limit(20)
  end

  # =====================================================
  # WORKFLOW SELECTION METHODS (NEW)
  # =====================================================
  
  # Show the workflow selection form for an inspection
  def select_workflow
    @inspection = Inspection.find(params[:id])
    
    # Calculate costs
    @labor_cost = calculate_labor_cost(@inspection)
    @parts_cost = calculate_parts_cost(@inspection)
    @total_cost = @labor_cost + @parts_cost
    
    # Get current rates
    @labor_rate = @inspection.labor_rate || current_user.agency&.settings&.labor_rate || 80
    @parts_markup = @inspection.parts_markup_percentage || 30
    
    # Get all jobs and parts for display
    @jobs = @inspection.inspection_jobs
    @parts_requests = @inspection.parts_requests
    
    disable_all_caching
  end
  
  # Process the workflow selection
  def process_workflow_selection
    @inspection = Inspection.find(params[:id])
    
    workflow_type = params[:workflow_type]
    labor_rate = params[:labor_rate].to_f
    parts_markup = params[:parts_markup].to_i
    notes = params[:workflow_notes]
    
    # Validate workflow type
    unless ['payment_before_work', 'work_before_payment'].include?(workflow_type)
      redirect_to vmcott_workshop_supervisor_select_workflow_path(@inspection),
                  alert: 'Please select a valid workflow type.'
      return
    end
    
    ActiveRecord::Base.transaction do
      # Update inspection with workflow selection
      @inspection.update!(
        workflow_type: workflow_type,
        workflow_selected_by_id: current_user.id,
        workflow_selected_at: Time.current,
        workflow_notes: notes,
        labor_rate: labor_rate,
        parts_markup_percentage: parts_markup,
        status: 'pending_procurement_quotation'
      )
      
      # Update job labor costs if rate changed
      if labor_rate != (@inspection.labor_rate_was || 80)
        @inspection.inspection_jobs.each do |job|
          new_labor_cost = (job.estimated_hours || 0) * labor_rate
          job.update!(estimated_labor_cost: new_labor_cost)
        end
      end
      
      # Update part costs if markup changed
      if parts_markup != (@inspection.parts_markup_percentage_was || 30)
        @inspection.parts_requests.each do |request|
          if request.part.present? && request.unit_price.present?
            new_price = request.unit_price * (1 + parts_markup / 100.0)
            request.update!(customer_price: new_price)
          end
        end
      end
      
      # Create notification for procurement team
      procurement_users = User.where(role: 'procurement').or(User.where(role: 'billing'))
      procurement_users.each do |procurement_user|
        Notification.create!(
          user: procurement_user,
          title: "Workflow Selected - Ready for Quotation",
          message: "Supervisor selected '#{workflow_type.humanize}' for vehicle #{@inspection.vehicle.license_plate}. Total: $#{'%.2f' % @inspection.total_estimated_cost}. Ready to create quotation.",
          link: vmcott_procurement_new_quotation_for_inspection_path(inspection_id: @inspection.id),
          notification_type: 'info',
          notifiable: @inspection
        )
      end
      
      flash[:notice] = "✅ Workflow '#{workflow_type.humanize}' selected. Procurement team will create the quotation."
    end
    
    redirect_to vmcott_workshop_supervisor_dashboard_path
  rescue => e
    Rails.logger.error "Error selecting workflow: #{e.message}"
    flash[:alert] = "Error selecting workflow: #{e.message}"
    redirect_to vmcott_workshop_supervisor_select_workflow_path(@inspection)
  end
  
  # Review workflow selection details
  def review_workflow
    @inspection = Inspection.find(params[:id])
    @workflow_selected = @inspection.workflow_selected_by_id.present?
    @jobs = @inspection.inspection_jobs
    @parts_requests = @inspection.parts_requests
    @labor_cost = calculate_labor_cost(@inspection)
    @parts_cost = calculate_parts_cost(@inspection)
    @total_cost = @labor_cost + @parts_cost
    
    disable_all_caching
  end
  
  # =====================================================
  # PRE-CHECK REVIEW METHODS
  # =====================================================
  
  def review_pre_check
    @job = InspectionJob.find(params[:id])
    @additional_findings = @job.additional_findings
    @mechanic = @job.assigned_mechanic
    
    disable_all_caching
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
    @vehicle = @parts_request.inspection&.vehicle
    
    disable_all_caching
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
    
    disable_all_caching
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
    
    disable_all_caching
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
    
    disable_all_caching
  end

  def work_order_show
    @work_order = WorkOrder.find(params[:id])
    @inspections = @work_order.inspections
    @jobs = @work_order.inspection_jobs
    @tasks = @work_order.job_tasks
    @findings = @work_order.findings
    @timeline = @work_order.timeline_events
    
    disable_all_caching
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
      .page(params[:page])
      .per(20)
    
    @status_filter = params[:status]
    @findings = @findings.where(status: @status_filter) if @status_filter.present?
    
    disable_all_caching
  end

  def finding_show
    @finding = Finding.find(params[:id])
    @work_order = @finding.work_order
    @tasks = @work_order&.job_tasks || []
    
    disable_all_caching
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
    
    disable_all_caching
  end

  def reports
    # Safe date parsing
    @start_date = if params[:start_date].present?
      begin
        Date.parse(params[:start_date])
      rescue
        1.week.ago.to_date
      end
    else
      1.week.ago.to_date
    end
    
    @end_date = if params[:end_date].present?
      begin
        Date.parse(params[:end_date])
      rescue
        Date.current
      end
    else
      Date.current
    end
    
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
    
    # NEW: Workflow selection stats
    @workflow_payment_before = Inspection.where(workflow_type: 'payment_before_work')
                                         .where(workflow_selected_at: @start_date.beginning_of_day..@end_date.end_of_day)
                                         .count
    
    @workflow_work_before = Inspection.where(workflow_type: 'work_before_payment')
                                      .where(workflow_selected_at: @start_date.beginning_of_day..@end_date.end_of_day)
                                      .count
    
    disable_all_caching
  end

  # =====================================================
  # JOB MANAGEMENT METHODS
  # =====================================================
  
  def approve_job
    @job = InspectionJob.find(params[:id])
    
    if @job.status == 'pending_approval'
      @job.update!(
        status: 'approved',
        approved_at: Time.current,
        approved_by: current_user
      )
      
      Notification.create!(
        user: @job.inspection.created_by,
        title: "Job Approved",
        message: "Job ##{@job.id} has been approved",
        link: vmcott_workshop_supervisor_job_path(@job),
        notification_type: 'success',
        notifiable: @job
      )
      
      flash[:notice] = "Job approved successfully."
    else
      flash[:alert] = "Job cannot be approved in its current state."
    end
    
    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end
  
  def reject_job
    @job = InspectionJob.find(params[:id])
    reason = params[:rejection_reason] || "No reason provided"
    
    if @job.status == 'pending_approval'
      @job.update!(
        status: 'rejected',
        rejected_at: Time.current,
        rejected_by: current_user,
        rejection_reason: reason
      )
      
      Notification.create!(
        user: @job.inspection.created_by,
        title: "Job Rejected",
        message: "Job ##{@job.id} was rejected. Reason: #{reason}",
        link: vmcott_workshop_supervisor_job_path(@job),
        notification_type: 'error',
        notifiable: @job
      )
      
      flash[:notice] = "Job rejected."
    else
      flash[:alert] = "Job cannot be rejected."
    end
    
    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end
  
  def assign_job
    @job = InspectionJob.find(params[:id])
    mechanic_id = params[:mechanic_id]
    
    if @job.status == 'approved' && mechanic_id.present?
      mechanic = User.find(mechanic_id)
      
      @job.update!(
        assigned_mechanic: mechanic,
        assigned_at: Time.current,
        status: 'assigned'
      )
      
      Notification.create!(
        user: mechanic,
        title: "New Job Assigned",
        message: "Job ##{@job.id} has been assigned to you",
        link: vmcott_mechanic_job_path(@job),
        notification_type: 'info',
        notifiable: @job
      )
      
      flash[:notice] = "Job assigned to #{mechanic.name}."
    else
      flash[:alert] = "Could not assign job."
    end
    
    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end
  
  def reassign_job
    @job = InspectionJob.find(params[:id])
    mechanic_id = params[:mechanic_id]
    reason = params[:reason]
    
    if mechanic_id.present?
      old_mechanic = @job.assigned_mechanic
      new_mechanic = User.find(mechanic_id)
      
      @job.update!(
        assigned_mechanic: new_mechanic,
        reassigned_at: Time.current,
        reassigned_by: current_user,
        reassign_reason: reason
      )
      
      if old_mechanic
        Notification.create!(
          user: old_mechanic,
          title: "Job Reassigned",
          message: "Job ##{@job.id} has been reassigned to #{new_mechanic.name}",
          link: vmcott_workshop_supervisor_job_path(@job),
          notification_type: 'warning',
          notifiable: @job
        )
      end
      
      Notification.create!(
        user: new_mechanic,
        title: "Job Reassigned to You",
        message: "Job ##{@job.id} has been reassigned to you. Reason: #{reason}",
        link: vmcott_mechanic_job_path(@job),
        notification_type: 'info',
        notifiable: @job
      )
      
      flash[:notice] = "Job reassigned to #{new_mechanic.name}."
    else
      flash[:alert] = "Could not reassign job."
    end
    
    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end
  
  def block_job
    @job = InspectionJob.find(params[:id])
    
    if @job.status == 'in_progress'
      @job.update!(
        status: 'blocked',
        blocked_at: Time.current,
        blocked_by: current_user,
        blocked_reason: params[:reason] || "Blocked by supervisor"
      )
      
      Notification.create!(
        user: @job.assigned_mechanic,
        title: "Job Blocked",
        message: "Job ##{@job.id} has been blocked. Reason: #{params[:reason] || 'Supervisor action'}",
        link: vmcott_workshop_supervisor_job_path(@job),
        notification_type: 'warning',
        notifiable: @job
      )
      
      flash[:notice] = "Job blocked."
    else
      flash[:alert] = "Job cannot be blocked."
    end
    
    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end
  
  def unblock_job
    @job = InspectionJob.find(params[:id])
    
    if @job.status == 'blocked'
      @job.update!(
        status: 'in_progress',
        unblocked_at: Time.current,
        unblocked_by: current_user
      )
      
      Notification.create!(
        user: @job.assigned_mechanic,
        title: "Job Unblocked",
        message: "Job ##{@job.id} has been unblocked. You can resume work.",
        link: vmcott_mechanic_job_path(@job),
        notification_type: 'success',
        notifiable: @job
      )
      
      flash[:notice] = "Job unblocked."
    else
      flash[:alert] = "Job is not blocked."
    end
    
    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end
  
  def send_to_qc
    @job = InspectionJob.find(params[:id])
    
    if @job.status == 'in_progress'
      @job.update!(
        status: 'pending_qc',
        qc_requested_at: Time.current,
        qc_requested_by: current_user
      )
      
      # Notify QC team
      qc_users = User.where(role: ['inspector', 'quality_control', 'admin'])
      Notification.create!(
        user: qc_users,
        title: "Job Ready for QC",
        message: "Job ##{@job.id} is ready for quality control review",
        link: vmcott_workshop_supervisor_job_path(@job),
        notification_type: 'info',
        notifiable: @job
      )
      
      flash[:notice] = "Job sent to Quality Control."
    else
      flash[:alert] = "Job cannot be sent to QC."
    end
    
    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end
  
  def pass_qc
    @job = InspectionJob.find(params[:id])
    
    if @job.status == 'pending_qc'
      @job.update!(
        status: 'approved_qc',
        qc_passed_at: Time.current,
        qc_passed_by: current_user,
        qc_notes: params[:qc_notes]
      )
      
      Notification.create!(
        user: @job.assigned_mechanic,
        title: "QC Passed",
        message: "Job ##{@job.id} has passed quality control",
        link: vmcott_workshop_supervisor_job_path(@job),
        notification_type: 'success',
        notifiable: @job
      )
      
      flash[:notice] = "Job passed QC."
    else
      flash[:alert] = "Job cannot be marked as passed QC."
    end
    
    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end
  
  def fail_qc
    @job = InspectionJob.find(params[:id])
    reason = params[:rework_instructions] || "Quality control failed"
    
    if @job.status == 'pending_qc'
      @job.update!(
        status: 'rework_needed',
        qc_failed_at: Time.current,
        qc_failed_by: current_user,
        qc_failure_reason: reason
      )
      
      Notification.create!(
        user: @job.assigned_mechanic,
        title: "QC Failed - Rework Required",
        message: "Job ##{@job.id} requires rework. Reason: #{reason}",
        link: vmcott_mechanic_job_path(@job),
        notification_type: 'error',
        notifiable: @job
      )
      
      flash[:alert] = "Job failed QC. Sent for rework."
    else
      flash[:alert] = "Job cannot be marked as failed QC."
    end
    
    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end
  
  def close_job
    @job = InspectionJob.find(params[:id])
    
    if @job.status == 'approved_qc'
      @job.update!(
        status: 'completed',
        completed_at: Time.current,
        completed_by: current_user
      )
      
      Notification.create!(
        user: @job.assigned_mechanic,
        title: "Job Completed",
        message: "Job ##{@job.id} has been completed and closed",
        link: vmcott_workshop_supervisor_job_path(@job),
        notification_type: 'success',
        notifiable: @job
      )
      
      flash[:notice] = "Job closed successfully."
    else
      flash[:alert] = "Job cannot be closed in its current state."
    end
    
    redirect_to vmcott_workshop_supervisor_jobs_path
  end
  
  def update_job
    @job = InspectionJob.find(params[:id])
    
    if @job.update(update_job_params)
      flash[:notice] = "Job updated successfully."
    else
      flash[:alert] = "Failed to update job: #{@job.errors.full_messages.join(', ')}"
    end
    
    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end
  
  def request_update
    @job = InspectionJob.find(params[:id])
    message = params[:message] || "Please provide an update on this job"
    
    Notification.create!(
      user: @job.assigned_mechanic,
      title: "Update Requested",
      message: "Supervisor requested an update: #{message}",
      link: vmcott_mechanic_job_path(@job),
      notification_type: 'info',
      notifiable: @job
    )
    
    flash[:notice] = "Update request sent to mechanic."
    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end
  
  def job_report
    @job = InspectionJob.find(params[:id])
    @work_sessions = @job.job_tasks.flat_map(&:work_sessions)
    @total_hours = @work_sessions.sum(&:duration_hours)
    @parts_used = @job.parts_requests.where(status: 'approved')
    
    respond_to do |format|
      format.html { render :report }
      format.pdf { render pdf: "job-#{@job.id}-report" }
    end
  end
  
  def job_history
    @job = InspectionJob.find(params[:id])
    @history = @job.audit_logs.order(created_at: :desc).limit(50)
    render :history
  end
  
  def print_job
    @job = InspectionJob.find(params[:id])
    @work_sessions = @job.job_tasks.flat_map(&:work_sessions)
    render :print, layout: false
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
      pending_parts_requests: PartsRequest.where(status: 'pending_approval').count,
      workflow_pending: Inspection.where(status: 'pending_procurement_quotation')
                                   .where(workflow_selected_by_id: nil).count
    }
  end
  
  def update_job_params
    params.require(:inspection_job).permit(:description, :estimated_hours, :priority, :notes)
  end
  
  # =====================================================
  # COST CALCULATION HELPERS
  # =====================================================
  
  def calculate_labor_cost(inspection)
    inspection.inspection_jobs.sum(:estimated_labor_cost).to_f
  end
  
  def calculate_parts_cost(inspection)
    inspection.parts_requests.sum(:total_cost).to_f
  end

  def workflow_pending
    @workflow_pending = Inspection
      .where(status: 'pending_procurement_quotation')
      .where(workflow_selected_by_id: nil)
      .includes(:vehicle, :inspection_jobs, :parts_requests)
      .order(created_at: :asc)
      .page(params[:page])
      .per(20)
    
    disable_all_caching
  end
  
  # =====================================================
  # CRITICAL: Disable ALL caching for this controller
  # Prevents white screen issues caused by Turbo caching
  # =====================================================
  def disable_all_caching
    # Disable Rails fragment caching
    expires_now
    
    # Disable browser caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0, private"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    # Disable Turbo caching completely - THIS IS THE KEY FIX
    response.headers["Turbo-Visit-Control"] = "reload"
    response.headers["Turbo-Cache-Control"] = "no-cache"
    
    # Disable Cloudflare or other proxy caching
    response.headers["X-Accel-Expires"] = "0"
    response.headers["Surrogate-Control"] = "no-store"
    
    # Disable Rails low-level caching for this request
    @_cache_hit = false
    
    # Log for debugging (optional - remove in production if too noisy)
    if Rails.env.development?
      Rails.logger.debug "🚫 Cache disabled for #{controller_name}##{action_name}"
    end
  end
end