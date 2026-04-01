# app/controllers/vmcott/workshop_supervisor/jobs_controller.rb
class Vmcott::WorkshopSupervisor::JobsController < ApplicationController
  layout "application"
  
  before_action :authenticate_user!
  before_action :require_supervisor
  before_action :set_inspection, only: [:update_jobs, :approve, :reject]
  before_action :set_job, only: [:show, :approve_job, :reject_job, :assign, :reassign, 
                                   :block, :unblock, :send_to_qc, :pass_qc, :fail_qc, 
                                   :close, :request_update, :update_job, :approve_parts_request, 
                                   :reject_parts_request, :review_parts_request]
  
  # Add debug logging
  before_action :log_request, only: [:approve_job, :reject_job, :assign, :send_to_qc, :update_job, :approve_parts_request, :reject_parts_request]
  
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
  end

  # =====================================================
  # PHASE 5: PARTS REQUEST APPROVAL METHODS
  # =====================================================

  def review_parts_request
    @parts_request = PartsRequest.find(params[:id])
    @job = @parts_request.inspection_job
    @vehicle = @parts_request.inspection&.vehicle
    @mechanic = @parts_request.requested_by || @job&.assigned_mechanic
    
    disable_all_caching
  end

  def approve_parts_request
    @parts_request = PartsRequest.find(params[:id])
    
    if @parts_request.update(
      status: 'approved',
      approved_at: Time.current,
      approved_by_id: current_user.id
    )
      # Check if part is in stock
      if @parts_request.part.present? && @parts_request.part.current_stock.to_i >= @parts_request.quantity.to_i
        @parts_request.update!(in_stock: true)
        
        # Notify inventory manager to issue parts
        inventory_managers = User.where(role: 'inventory_manager')
        inventory_managers.find_each do |im|
          Notification.create!(
            user: im,
            title: "📦 Parts Ready to Issue",
            message: "#{@parts_request.quantity}x #{@parts_request.part_name} is in stock and ready for issue to job ##{@parts_request.inspection_job_id}",
            link: vmcott_inventory_manager_dashboard_path,
            notification_type: 'info',
            notifiable: @parts_request
          )
        end
      else
        # Part needs to be ordered
        @parts_request.update!(
          status: 'needs_order',
          in_stock: false
        )
        
        # Notify procurement to order parts
        procurement_users = User.where(role: 'procurement')
        procurement_users.find_each do |pu|
          Notification.create!(
            user: pu,
            title: "📦 Parts Need Ordering",
            message: "#{@parts_request.quantity}x #{@parts_request.part_name} needs to be ordered for job ##{@parts_request.inspection_job_id}",
            link: vmcott_procurement_dashboard_path,
            notification_type: 'warning',
            notifiable: @parts_request
          )
        end
      end
      
      # Notify the mechanic who requested the part
      if @parts_request.requested_by.present?
        Notification.create!(
          user: @parts_request.requested_by,
          title: "✅ Parts Request Approved",
          message: "Your request for #{@parts_request.quantity}x #{@parts_request.part_name} has been approved.",
          link: vmcott_mechanic_job_path(@parts_request.inspection_job),
          notification_type: 'success',
          notifiable: @parts_request
        )
      end
      
      # Notify the mechanic assigned to the job (if different from requester)
      if @parts_request.inspection_job&.assigned_mechanic.present? && 
         @parts_request.inspection_job.assigned_mechanic != @parts_request.requested_by
        Notification.create!(
          user: @parts_request.inspection_job.assigned_mechanic,
          title: "Parts Request Approved",
          message: "Parts request for #{@parts_request.quantity}x #{@parts_request.part_name} has been approved.",
          link: vmcott_mechanic_job_path(@parts_request.inspection_job),
          notification_type: 'success',
          notifiable: @parts_request
        )
      end
      
      flash[:notice] = "✅ Parts request approved. #{@parts_request.in_stock? ? 'Parts are in stock and ready for issue.' : 'Parts have been sent for ordering.'}"
      
      # Redirect back to the job page
      if @parts_request.inspection_job.present?
        redirect_to vmcott_workshop_supervisor_job_path(@parts_request.inspection_job)
      else
        redirect_to vmcott_workshop_supervisor_dashboard_path
      end
    else
      flash[:alert] = "Error approving parts request: #{@parts_request.errors.full_messages.join(', ')}"
      redirect_back(fallback_location: vmcott_workshop_supervisor_dashboard_path)
    end
  rescue => e
    Rails.logger.error "Error approving parts request: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    flash[:alert] = "Error approving parts request: #{e.message}"
    redirect_back(fallback_location: vmcott_workshop_supervisor_dashboard_path)
  end

  def reject_parts_request
    @parts_request = PartsRequest.find(params[:id])
    reason = params[:reason] || params[:rejection_reason] || "Not approved at this time"
    
    if @parts_request.update(
      status: 'rejected',
      rejected_at: Time.current,
      rejected_by_id: current_user.id,
      rejection_reason: reason
    )
      # Notify the mechanic who requested the part
      if @parts_request.requested_by.present?
        Notification.create!(
          user: @parts_request.requested_by,
          title: "❌ Parts Request Rejected",
          message: "Your request for #{@parts_request.quantity}x #{@parts_request.part_name} was rejected. Reason: #{reason}",
          link: vmcott_mechanic_job_path(@parts_request.inspection_job),
          notification_type: 'error',
          notifiable: @parts_request
        )
      end
      
      # Notify the mechanic assigned to the job (if different from requester)
      if @parts_request.inspection_job&.assigned_mechanic.present? && 
         @parts_request.inspection_job.assigned_mechanic != @parts_request.requested_by
        Notification.create!(
          user: @parts_request.inspection_job.assigned_mechanic,
          title: "Parts Request Rejected",
          message: "Parts request for #{@parts_request.quantity}x #{@parts_request.part_name} was rejected. Reason: #{reason}",
          link: vmcott_mechanic_job_path(@parts_request.inspection_job),
          notification_type: 'error',
          notifiable: @parts_request
        )
      end
      
      flash[:alert] = "❌ Parts request rejected: #{reason}"
      
      # Redirect back to the job page
      if @parts_request.inspection_job.present?
        redirect_to vmcott_workshop_supervisor_job_path(@parts_request.inspection_job)
      else
        redirect_to vmcott_workshop_supervisor_dashboard_path
      end
    else
      flash[:alert] = "Error rejecting parts request: #{@parts_request.errors.full_messages.join(', ')}"
      redirect_back(fallback_location: vmcott_workshop_supervisor_dashboard_path)
    end
  rescue => e
    Rails.logger.error "Error rejecting parts request: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    flash[:alert] = "Error rejecting parts request: #{e.message}"
    redirect_back(fallback_location: vmcott_workshop_supervisor_dashboard_path)
  end

  def approve_job
    Rails.logger.info "=" * 50
    Rails.logger.info "APPROVE_JOB called with params: #{params.inspect}"
    Rails.logger.info "Job ID: #{params[:id]}"
    Rails.logger.info "=" * 50
    
    if @job.status == 'pending_approval'
      @job.update!(
        status: 'approved',
        approved_at: Time.current,
        approved_by: current_user
      )

      if @job.inspection.created_by_id.present?
        created_by = User.find_by(id: @job.inspection.created_by_id)
        if created_by
          Notification.create!(
            user: created_by,
            title: "Job Approved",
            message: "Job ##{@job.id} has been approved",
            link: vmcott_workshop_supervisor_job_path(@job),
            notification_type: 'success',
            notifiable: @job
          )
        end
      end

      flash[:notice] = "Job approved successfully."
    else
      flash[:alert] = "Job cannot be approved in its current state."
    end

    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def reject_job
    Rails.logger.info "=" * 50
    Rails.logger.info "REJECT_JOB called with params: #{params.inspect}"
    Rails.logger.info "Job ID: #{params[:id]}"
    Rails.logger.info "=" * 50
    
    reason = params[:rejection_reason] || "No reason provided"

    if @job.status == 'pending_approval'
      @job.update!(
        status: 'rejected',
        rejected_at: Time.current,
        rejected_by: current_user,
        rejection_reason: reason
      )

      if @job.inspection.created_by_id.present?
        created_by = User.find_by(id: @job.inspection.created_by_id)
        if created_by
          Notification.create!(
            user: created_by,
            title: "Job Rejected",
            message: "Job ##{@job.id} was rejected. Reason: #{reason}",
            link: vmcott_workshop_supervisor_job_path(@job),
            notification_type: 'error',
            notifiable: @job
          )
        end
      end

      flash[:notice] = "Job rejected."
    else
      flash[:alert] = "Job cannot be rejected."
    end

    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def assign
    Rails.logger.info "=" * 50
    Rails.logger.info "ASSIGN called with params: #{params.inspect}"
    Rails.logger.info "Job ID: #{params[:id]}"
    Rails.logger.info "Mechanic ID: #{params[:mechanic_id]}"
    Rails.logger.info "=" * 50
    
    mechanic_id = params[:mechanic_id]
    
    if mechanic_id.present?
      mechanic = User.find(mechanic_id)
      
      # Create or update MechanicAssignment
      assignment = MechanicAssignment.find_or_initialize_by(
        inspection_job: @job,
        mechanic: mechanic
      )

      assignment.update!(
        status: 'assigned',
        started_at: Time.current,
        mechanic_notes: "Assigned by #{current_user.name}"
      )

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
      flash[:alert] = "Please select a mechanic"
    end
    
    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def reassign
    Rails.logger.info "=" * 50
    Rails.logger.info "REASSIGN called with params: #{params.inspect}"
    Rails.logger.info "Job ID: #{params[:id]}"
    Rails.logger.info "=" * 50
    
    mechanic_id = params[:mechanic_id]
    
    if mechanic_id.present?
      old_mechanic = @job.assigned_mechanic
      new_mechanic = User.find(mechanic_id)

      # Update MechanicAssignment
      assignment = MechanicAssignment.find_by(inspection_job: @job)

      if assignment
        assignment.update!(
          mechanic: new_mechanic,
          status: 'assigned',
          mechanic_notes: "#{assignment.mechanic_notes}\nReassigned from #{old_mechanic&.name} by #{current_user.name}: #{params[:reason]}"
        )
      else
        MechanicAssignment.create!(
          inspection_job: @job,
          mechanic: new_mechanic,
          status: 'assigned',
          mechanic_notes: "Assigned by #{current_user.name} (reassignment): #{params[:reason]}"
        )
      end

      @job.update!(
        assigned_mechanic: new_mechanic,
        reassigned_at: Time.current,
        reassigned_by: current_user,
        reassign_reason: params[:reason]
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
        message: "Job ##{@job.id} has been reassigned to you. Reason: #{params[:reason]}",
        link: vmcott_mechanic_job_path(@job),
        notification_type: 'info',
        notifiable: @job
      )

      flash[:notice] = "Job reassigned to #{new_mechanic.name}."
    else
      flash[:alert] = "Please select a mechanic"
    end
    
    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def block
    Rails.logger.info "=" * 50
    Rails.logger.info "BLOCK called with params: #{params.inspect}"
    Rails.logger.info "=" * 50
    
    if @job.status == 'in_progress'
      # Update MechanicAssignment
      assignment = MechanicAssignment.find_by(inspection_job: @job)
      if assignment
        assignment.update!(
          status: 'blocked',
          mechanic_notes: "#{assignment.mechanic_notes}\nBlocked by #{current_user.name}: #{params[:reason]}"
        )
      end

      @job.update!(
        status: 'blocked',
        blocked_at: Time.current,
        blocked_by: current_user,
        blocked_reason: params[:reason] || "Blocked by supervisor"
      )

      if @job.assigned_mechanic_id.present?
        mechanic = User.find_by(id: @job.assigned_mechanic_id)
        if mechanic
          Notification.create!(
            user: mechanic,
            title: "Job Blocked",
            message: "Job ##{@job.id} has been blocked. Reason: #{params[:reason] || 'Supervisor action'}",
            link: vmcott_workshop_supervisor_job_path(@job),
            notification_type: 'warning',
            notifiable: @job
          )
        end
      end

      flash[:notice] = "Job blocked."
    else
      flash[:alert] = "Job cannot be blocked."
    end

    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def unblock
    Rails.logger.info "=" * 50
    Rails.logger.info "UNBLOCK called with params: #{params.inspect}"
    Rails.logger.info "=" * 50
    
    if @job.status == 'blocked'
      # Update MechanicAssignment
      assignment = MechanicAssignment.find_by(inspection_job: @job)
      if assignment
        assignment.update!(
          status: 'in_progress',
          mechanic_notes: "#{assignment.mechanic_notes}\nUnblocked by #{current_user.name}"
        )
      end

      @job.update!(
        status: 'in_progress',
        unblocked_at: Time.current,
        unblocked_by: current_user
      )

      if @job.assigned_mechanic_id.present?
        mechanic = User.find_by(id: @job.assigned_mechanic_id)
        if mechanic
          Notification.create!(
            user: mechanic,
            title: "Job Unblocked",
            message: "Job ##{@job.id} has been unblocked. You can resume work.",
            link: vmcott_mechanic_job_path(@job),
            notification_type: 'success',
            notifiable: @job
          )
        end
      end

      flash[:notice] = "Job unblocked."
    else
      flash[:alert] = "Job is not blocked."
    end

    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def send_to_qc
    Rails.logger.info "=" * 50
    Rails.logger.info "SEND_TO_QC called with params: #{params.inspect}"
    Rails.logger.info "Job ID: #{params[:id]}"
    Rails.logger.info "Job Status: #{@job&.status}"
    Rails.logger.info "=" * 50
    
    # Check if there are any pending parts requests
    pending_parts = @job.parts_requests.where(status: 'requested').exists?
    Rails.logger.info "Pending parts: #{pending_parts}"

    if pending_parts
      flash[:alert] = "Cannot send to QC. There are pending parts requests that need to be approved or rejected first."
      redirect_to vmcott_workshop_supervisor_job_path(@job) and return
    end

    if @job.status == 'in_progress'
      # Update MechanicAssignment with QC request
      assignment = MechanicAssignment.find_by(inspection_job: @job)
      if assignment
        assignment.update!(
          qc_requested_at: Time.current,
          mechanic_notes: "#{assignment.mechanic_notes}\nQC requested at #{Time.current.strftime('%Y-%m-%d %H:%M')} by #{current_user.name}"
        )
      end

      # Update the job status to 'completed'
      @job.update!(
        status: 'completed',
        completed_at: Time.current
      )

      # Create individual notifications for each QC user
      qc_users = User.where(role: ['inspector', 'quality_control', 'admin'])
      
      qc_users.find_each do |user|
        Notification.create!(
          user: user,
          title: "Job Ready for QC",
          message: "Job ##{@job.id} is ready for quality control review",
          link: vmcott_workshop_supervisor_job_path(@job),
          notification_type: 'info',
          notifiable: @job
        )
      end

      flash[:notice] = "Job sent to Quality Control."
    else
      flash[:alert] = "Job cannot be sent to QC (current status: #{@job.status})."
    end

    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def pass_qc
    Rails.logger.info "=" * 50
    Rails.logger.info "PASS_QC called with params: #{params.inspect}"
    Rails.logger.info "=" * 50
    
    if @job.status == 'completed'
      # Update MechanicAssignment with QC result
      assignment = MechanicAssignment.find_by(inspection_job: @job)
      if assignment
        assignment.update!(
          qc_completed_at: Time.current,
          qc_notes: params[:qc_notes],
          status: 'completed',
          mechanic_notes: "#{assignment.mechanic_notes}\nQC PASSED at #{Time.current.strftime('%Y-%m-%d %H:%M')} by #{current_user.name}"
        )
      end

      # Update only attributes that exist in inspection_jobs
      @job.update!(
        verification_status: 'verified',
        verified_at: Time.current,
        verified_by_mechanic_id: current_user.id,
        qc_notes: params[:qc_notes]
      )

      if @job.assigned_mechanic_id.present?
        mechanic = User.find_by(id: @job.assigned_mechanic_id)
        if mechanic
          Notification.create!(
            user: mechanic,
            title: "QC Passed",
            message: "Job ##{@job.id} has passed quality control",
            link: vmcott_workshop_supervisor_job_path(@job),
            notification_type: 'success',
            notifiable: @job
          )
        end
      end

      flash[:notice] = "Job passed QC."
    else
      flash[:alert] = "Job cannot be marked as passed QC."
    end

    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def fail_qc
    Rails.logger.info "=" * 50
    Rails.logger.info "FAIL_QC called with params: #{params.inspect}"
    Rails.logger.info "=" * 50
    
    reason = params[:rework_instructions] || "Quality control failed"

    if @job.status == 'completed'
      # Update MechanicAssignment with QC failure
      assignment = MechanicAssignment.find_by(inspection_job: @job)
      if assignment
        assignment.update!(
          qc_completed_at: Time.current,
          qc_notes: "FAILED: #{reason}",
          status: 'rework_needed',
          mechanic_notes: "#{assignment.mechanic_notes}\nQC FAILED at #{Time.current.strftime('%Y-%m-%d %H:%M')} by #{current_user.name}: #{reason}"
        )
      end

      # Update only attributes that exist in inspection_jobs
      @job.update!(
        verification_status: 'pending',
        status: 'assigned',  # Send back to assigned for rework
        qc_notes: "FAILED: #{reason}",
        notes: "#{@job.notes}\n\n[QC FAILED] #{Time.current.strftime('%Y-%m-%d %H:%M')} by #{current_user.name}: #{reason}"
      )

      if @job.assigned_mechanic_id.present?
        mechanic = User.find_by(id: @job.assigned_mechanic_id)
        if mechanic
          Notification.create!(
            user: mechanic,
            title: "QC Failed - Rework Required",
            message: "Job ##{@job.id} requires rework. Reason: #{reason}",
            link: vmcott_mechanic_job_path(@job),
            notification_type: 'error',
            notifiable: @job
          )
        end
      end

      flash[:alert] = "Job failed QC. Sent for rework."
    else
      flash[:alert] = "Job cannot be marked as failed QC."
    end

    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def close
    Rails.logger.info "=" * 50
    Rails.logger.info "CLOSE called with params: #{params.inspect}"
    Rails.logger.info "=" * 50
    
    if @job.verification_status == 'verified'
      @job.update!(
        status: 'completed',
        completed_at: Time.current,
        completed_by: current_user
      )

      if @job.assigned_mechanic_id.present?
        mechanic = User.find_by(id: @job.assigned_mechanic_id)
        if mechanic
          Notification.create!(
            user: mechanic,
            title: "Job Completed",
            message: "Job ##{@job.id} has been completed and closed",
            link: vmcott_workshop_supervisor_job_path(@job),
            notification_type: 'success',
            notifiable: @job
          )
        end
      end

      flash[:notice] = "Job closed successfully."
    else
      flash[:alert] = "Job cannot be closed in its current state."
    end

    redirect_to vmcott_workshop_supervisor_jobs_path
  end

  def request_update
    Rails.logger.info "=" * 50
    Rails.logger.info "REQUEST_UPDATE called with params: #{params.inspect}"
    Rails.logger.info "=" * 50
    
    message = params[:message] || "Please provide an update on this job"

    if @job.assigned_mechanic_id.present?
      mechanic = User.find_by(id: @job.assigned_mechanic_id)
      if mechanic
        Notification.create!(
          user: mechanic,
          title: "Update Requested",
          message: "Supervisor requested an update: #{message}",
          link: vmcott_mechanic_job_path(@job),
          notification_type: 'info',
          notifiable: @job
        )
      end
    end

    flash[:notice] = "Update request sent to mechanic."
    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def update_job
    Rails.logger.info "=" * 50
    Rails.logger.info "UPDATE_JOB called with params: #{params.inspect}"
    Rails.logger.info "Commit: #{params[:commit]}"
    Rails.logger.info "Add Note present: #{params[:add_note].present?}"
    Rails.logger.info "=" * 50
    
    # Check if this is a note addition (from the note modal)
    if params[:commit] == "Add Note" || params[:add_note].present?
      new_note = params[:inspection_job]&.[](:notes) || params[:notes]
      Rails.logger.info "New note: #{new_note}"
      
      if new_note.present?
        timestamp = Time.current.strftime("%Y-%m-%d %H:%M")
        current_notes = @job.notes.to_s
        updated_notes = "#{current_notes}\n\n[#{timestamp}] #{current_user.name}: #{new_note}"
        
        if @job.update(notes: updated_notes)
          flash[:notice] = "Note added successfully."
        else
          flash[:alert] = "Failed to add note: #{@job.errors.full_messages.join(', ')}"
        end
      else
        flash[:alert] = "Note cannot be blank."
      end
    else
      # Regular job update from edit modal
      if params[:inspection_job].present? && @job.update(update_job_params)
        flash[:notice] = "Job updated successfully."
      else
        flash[:alert] = "Failed to update job. Please check your input."
      end
    end
    
    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def review
    @inspection = Inspection.includes(
      :vehicle,
      :inspector,
      inspection_jobs: []
    ).find(params[:inspection_id])

    @pending_approval = @inspection.inspection_jobs.where(status: 'pending_approval')
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
          status: 'pending_approval'
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
    # Mark inspection as approved
    @inspection.update!(
      status: :approved,
      approved_at: Time.current,
      supervisor_id: current_user.id
    )
    
    # Update all jobs to approved status
    @inspection.inspection_jobs.update_all(
      status: 'approved',
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
      status: :received,
      rejection_reason: reason
    )
    
    # Notify inspector
    if @inspection.inspector_id.present?
      inspector = User.find_by(id: @inspection.inspector_id)
      if inspector
        Notification.create!(
          user: inspector,
          title: "Job Recommendations Rejected",
          message: "Your job recommendations for #{@inspection.vehicle&.license_plate || 'vehicle'} need revision: #{reason}",
          link: vmcott_inspector_inspection_path(@inspection),
          notification_type: 'warning',
          notifiable: @inspection
        )
      end
    end
    
    redirect_to vmcott_workshop_supervisor_dashboard_path, 
                alert: "Jobs rejected and sent back to inspector"
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
  
  def log_request
    Rails.logger.info "=" * 50
    Rails.logger.info "Action: #{action_name}"
    Rails.logger.info "Params: #{params.except(:controller, :action).inspect}"
    Rails.logger.info "=" * 50
  end
  
  def set_inspection
    @inspection = Inspection.find(params[:inspection_id])
  end
  
  def set_job
    @job = InspectionJob.find(params[:id])
  end
  
  def require_supervisor
    unless current_user.role == 'workshop_supervisor' || current_user.admin?
      redirect_to root_path, alert: "Access denied. Supervisor privileges required."
    end
  end
  
  def update_job_params
    params.require(:inspection_job).permit(:description, :estimated_hours, :priority, :notes)
  end
  
  def notify_mechanics(inspection)
    # Find all mechanics
    mechanics = User.where(role: 'mechanic')
    
    # Create a notification for each mechanic individually
    mechanics.find_each do |mechanic|
      Notification.create!(
        user: mechanic,
        title: "New Jobs Available!",
        message: "Work order for #{inspection.vehicle&.license_plate || 'vehicle'} is ready. #{inspection.inspection_jobs.count} jobs available.",
        link: "/vmcott/mechanic/dashboard",
        notification_type: 'success',
        notifiable: inspection
      )
    end
  rescue => e
    Rails.logger.error "Failed to notify mechanics: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end
  
  # Add disable_all_caching method if needed
  def disable_all_caching
    expires_now
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0, private"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    response.headers["Turbo-Visit-Control"] = "reload"
    response.headers["Turbo-Cache-Control"] = "no-cache"
  end
end