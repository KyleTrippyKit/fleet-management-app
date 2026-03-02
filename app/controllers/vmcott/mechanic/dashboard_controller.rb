# app/controllers/vmcott/mechanic/dashboard_controller.rb
class Vmcott::Mechanic::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_mechanic
  before_action :set_job_context, only: [:show_job, :start_job, :update_progress, :log_parts_used, :request_qc]

  def index
    @assigned_jobs = MechanicAssignment.includes(inspection_job: { inspection: :vehicle })
                                       .where(mechanic_id: current_user.id, status: ['assigned', 'in_progress'])
                                       .order(created_at: :asc)

    # Jobs needing verification (inspector-suspected jobs)
    @jobs_needing_verification = InspectionJob.includes(inspection: :vehicle)
                                              .where(assigned_mechanic_id: nil, 
                                                     completed_at: nil,
                                                     verification_status: 'pending')
                                              .order(created_at: :asc)

    @available_jobs = InspectionJob.includes(inspection: :vehicle)
                                   .where(assigned_mechanic_id: nil, completed_at: nil)
                                   .where(verification_status: 'approved')
                                   .where('requires_part_approval = false OR parts_approved = true')
                                   .order(created_at: :asc)

    @jobs_by_vehicle = @assigned_jobs.map(&:inspection_job).compact.group_by { |job| job.inspection&.vehicle }

    @completed_today = MechanicAssignment.where(mechanic_id: current_user.id)
                                         .where('completed_at >= ?', Date.current.beginning_of_day)
                                         .count

    @waiting_parts = MechanicAssignment.where(mechanic_id: current_user.id, status: 'waiting_parts')
                                       .includes(:inspection_job)
    
    @pending_qc = Inspection.joins(inspection_jobs: :mechanic_assignments)
                            .where(mechanic_assignments: { mechanic_id: current_user.id })
                            .where(status: 'ready_for_qc')
                            .distinct
                            .count
                           
    @recently_completed = InspectionJob.where(assigned_mechanic_id: current_user.id)
                                       .where.not(completed_at: nil)
                                       .order(completed_at: :desc)
                                       .limit(10)
    
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
    @jobs_needing_verification = []
    @available_jobs = []
    @jobs_by_vehicle = {}
    @completed_today = 0
    @waiting_parts = []
    @pending_qc = 0
    @recently_completed = []
    @taken_jobs = []
  end

  def show_job
    @inspection = @job&.inspection
    @vehicle = @inspection&.vehicle
    @parts = @job&.inspection_job_parts&.includes(:part) || []
    
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

  # Verification actions
  def verification_queue
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
    
    # Auto-assign for verification
    @job.update(assigned_mechanic_id: current_user.id) if @job.assigned_mechanic_id.nil?
    
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
        # Original job is correct - update parts requests
        @job.inspection_job_parts.each do |job_part|
          part = job_part.part
          if part && part.current_stock >= job_part.quantity
            # Create approved parts request
            PartsRequest.create!(
              inspection: @job.inspection,
              inspection_job: @job,
              part: part,
              quantity: job_part.quantity,
              status: 'approved',
              in_stock: true
            )
          else
            # Create pending parts request
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
        # Create new corrected job based on mechanic's findings
        corrected_job = @job.inspection.inspection_jobs.create!(
          description: params[:corrected_description],
          recommendation_source: 'mechanic',
          verification_status: 'approved',
          parent_job_id: @job.id,
          priority: @job.priority
        )
        
        # Handle parts from params
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
        
        # Mark original job as superseded
        @job.update!(status: 'superseded')
        flash[:notice] = "Corrected job created based on your findings."
        
      when 'rejected'
        # No issue found - close the job
        @job.update!(
          completed_at: Time.current,
          status: 'cancelled'
        )
        flash[:notice] = "Job marked as not needed."
      end

      # Check if all jobs for this inspection are now approved/verified
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

  # Additional finding (while repairing)
  def new_additional_finding
    @inspection = Inspection.find(params[:inspection_id])
    @job = @inspection.inspection_jobs.new
    render 'vmcott/mechanic/dashboard/new_additional_finding'
  end

  def create_additional_finding
    @inspection = Inspection.find(params[:inspection_id])
    
    ActiveRecord::Base.transaction do
      @job = @inspection.inspection_jobs.create!(
        description: params[:job][:description],
        recommendation_source: 'mechanic',
        verification_status: 'approved',
        verified_by_mechanic_id: current_user.id,
        verified_at: Time.current,
        mechanic_notes: params[:job][:mechanic_notes],
        priority: params[:job][:priority] || 'normal'
      )

      if params[:parts].present?
        params[:parts].each do |part_data|
          quantity = part_data[:quantity].to_i
          
          if part_data[:is_custom] == 'true'
            @job.inspection_job_parts.create!(
              custom_part_name: part_data[:custom_name],
              quantity: quantity
            )
            PartsRequest.create!(
              inspection: @inspection,
              inspection_job: @job,
              custom_part_name: part_data[:custom_name],
              quantity: quantity,
              status: 'pending',
              in_stock: false
            )
          else
            part = Part.find(part_data[:part_id])
            @job.inspection_job_parts.create!(
              part: part,
              quantity: quantity
            )
            
            if part.current_stock >= quantity
              PartsRequest.create!(
                inspection: @inspection,
                inspection_job: @job,
                part: part,
                quantity: quantity,
                status: 'approved',
                in_stock: true
              )
            else
              PartsRequest.create!(
                inspection: @inspection,
                inspection_job: @job,
                part: part,
                quantity: quantity,
                status: 'pending',
                in_stock: false
              )
            end
          end
        end
      end
      
      # Update inspection status if needed
      if @inspection.status == 'pending_mechanic_verification'
        @inspection.update!(status: 'approved_for_repair')
      end
    end

    redirect_to vmcott_mechanic_job_path(@job), notice: "Additional finding logged successfully."
  rescue => e
    Rails.logger.error "Error in create_additional_finding: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    flash[:alert] = "An error occurred: #{e.message}"
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
    
    job.update!(assigned_mechanic_id: current_user.id)
    
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

    part.update!(current_stock: part.current_stock - qty)
    
    assignment = MechanicAssignment.find_by(inspection_job_id: @job.id, mechanic_id: current_user.id)
    if assignment
      assignment.update(
        mechanic_notes: "#{assignment.mechanic_notes}\n[PARTS] Used #{qty}x #{part.name} (Stock left: #{part.current_stock})"
      )
    end
    
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
    
    assignment = MechanicAssignment.find_by(inspection_job_id: @job.id, mechanic_id: current_user.id)
    if assignment
      assignment.update!(
        status: 'completed', 
        completed_at: Time.current
      )
    end
    
    @job.update!(
      completed_at: Time.current
    )

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
end