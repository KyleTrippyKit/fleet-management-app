class Vmcott::Inspector::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_inspector
  before_action :set_inspection, only: [:show_inspection, :qc_inspection, :complete_qc]

  def index
    @pending_inspections = ReceptionLog.where(status: 'checked_in')
                                       .includes(:vehicle)
                                       .order(created_at: :desc)
    @in_progress = Inspection.where(inspector: current_user, status: 'pending_inspection')
    @recent_completed = Inspection.where(inspector: current_user)
                                   .where(status: ['inspection_completed', 'approved_for_repair', 'ready_for_pickup', 'completed'])
                                   .order(created_at: :desc)
                                   .limit(5)
  end

  def new_inspection
    @vehicle = Vehicle.find_by(id: params[:vehicle_id])
    
    if @vehicle.nil?
      flash[:alert] = "Vehicle not found"
      redirect_to vmcott_inspector_dashboard_path and return
    end
    
    @inspection = Inspection.new(vehicle: @vehicle, inspector: current_user)
    @job_templates = JobTemplate.for_vehicle(@vehicle).active
  end

  def create_inspection
    @vehicle = Vehicle.find_by(id: params[:vehicle_id])
    
    if @vehicle.nil?
      flash[:alert] = "Vehicle not found"
      redirect_to vmcott_inspector_dashboard_path and return
    end

    @inspection = Inspection.new(
      vehicle: @vehicle,
      inspector: current_user,
      mileage_at_inspection: params[:mileage],
      notes: params[:notes],
      next_service_mileage: params[:next_service_mileage],
      next_service_date: params[:next_service_date],
      status: 'inspection_completed'  # Will be updated based on parts/jobs
    )

    ActiveRecord::Base.transaction do
      @inspection.save!

      # Track counts
      jobs_added = 0
      parts_need_ordering = false
      has_parts = false

      # Process parts from all sources
      if params[:parts].present?
        # Group parts by job
        parts_by_job = params[:parts].group_by { |p| [p[:job_type], p[:job_id]] }
        
        parts_by_job.each do |(job_type, job_id), job_parts|
          # Find or create the job
          job = if job_type == 'template'
                  template = JobTemplate.find_by(id: job_id)
                  if template.nil?
                    Rails.logger.error "JobTemplate with id #{job_id} not found"
                    next
                  end
                  @inspection.inspection_jobs.find_or_create_by!(
                    job_template: template,
                    description: template.name,
                    priority: 'normal'
                  )
                elsif job_type == 'custom'
                  # For custom jobs, find by temp_id in params
                  custom_job_data = params[:custom_jobs]&.find { |cj| cj[:temp_id] == job_id }
                  @inspection.inspection_jobs.create!(
                    description: custom_job_data&.[](:description) || "Custom Job",
                    priority: 'normal'
                  )
                else
                  next
                end

          jobs_added += 1

          # Process each part for this job
          job_parts.each do |part_data|
            quantity = part_data[:quantity].to_i
            is_custom = part_data[:is_custom] == 'true'

            if is_custom
              # Custom part - always needs ordering
              parts_need_ordering = true
              has_parts = true
              
              # Create inspection job part with custom name
              job.inspection_job_parts.create!(
                custom_part_name: part_data[:custom_name],
                quantity: quantity
              )

              # Create parts request for procurement
              PartsRequest.create!(
                inspection: @inspection,
                custom_part_name: part_data[:custom_name],
                quantity: quantity,
                status: 'pending',
                in_stock: false
              )
            else
              # Inventory part
              part = Part.find_by(id: part_data[:part_id])
              
              if part.nil?
                Rails.logger.error "Part with id #{part_data[:part_id]} not found"
                next
              end
              
              has_parts = true
              
              # Create inspection job part
              job.inspection_job_parts.create!(
                part: part,
                quantity: quantity
              )

              # Check stock
              if part.current_stock >= quantity
                # In stock - can be used immediately
                PartsRequest.create!(
                  inspection: @inspection,
                  part: part,
                  quantity: quantity,
                  status: 'approved',
                  in_stock: true
                )
              else
                # Out of stock - needs ordering
                parts_need_ordering = true
                PartsRequest.create!(
                  inspection: @inspection,
                  part: part,
                  quantity: quantity,
                  status: 'pending',
                  in_stock: false
                )
              end
            end
          end
        end
      end

      # Update vehicle mileage
      @inspection.vehicle.update(mileage: params[:mileage]) if params[:mileage].present?

      # CRITICAL WORKFLOW LOGIC - Determine next step based on jobs and parts
      
      # CASE 1: NO JOBS ADDED - Inspection only (no work needed)
      if jobs_added == 0
        @inspection.update!(
          status: 'ready_for_pickup',
          ready_for_pickup_at: Time.current,
          final_inspection_completed_at: Time.current,
          final_inspector_id: current_user.id,
          notes: @inspection.notes.to_s + "\n\n[Inspection Only] No work required. Vehicle ready for immediate pickup."
        )
        
        # Create a service record without charges
        Rails.logger.info "Inspection only for vehicle #{@vehicle.license_plate} - Ready for pickup"
        
        # Notify receptionist that vehicle is ready for pickup
        if @inspection.respond_to?(:notify_receptionist_for_pickup!)
          @inspection.notify_receptionist_for_pickup!
        end
        
        flash[:notice] = "Inspection completed. No work required - vehicle is ready for pickup."
      
      # CASE 2: JOBS ADDED BUT NO PARTS NEEDED
      elsif jobs_added > 0 && !has_parts
        @inspection.update!(
          status: 'approved_for_repair',
          notes: @inspection.notes.to_s + "\n\nJobs require no parts. Ready for mechanics."
        )
        
        # Notify mechanics directly (skip parts coordinator)
        @inspection.notify_mechanics! if @inspection.respond_to?(:notify_mechanics!)
        
        flash[:notice] = "Inspection completed. Jobs require no parts - mechanics notified."
      
      # CASE 3: JOBS ADDED WITH PARTS - ALL IN STOCK
      elsif jobs_added > 0 && has_parts && !parts_need_ordering
        @inspection.update!(
          status: 'approved_for_repair',
          notes: @inspection.notes.to_s + "\n\nAll parts in stock. Ready for mechanics."
        )
        
        # Notify mechanics directly (skip parts coordinator)
        @inspection.notify_mechanics! if @inspection.respond_to?(:notify_mechanics!)
        
        flash[:notice] = "Inspection completed. All parts in stock - mechanics notified."
      
      # CASE 4: JOBS ADDED WITH PARTS - SOME NEED ORDERING
      elsif jobs_added > 0 && has_parts && parts_need_ordering
        @inspection.update!(
          status: 'parts_coordinator_review',
          parts_coordinator_notified_at: Time.current,
          notes: @inspection.notes.to_s + "\n\nSome parts need ordering. Sent to parts coordinator."
        )
        
        # Notify parts coordinator
        @inspection.notify_parts_coordinator! if @inspection.respond_to?(:notify_parts_coordinator!)
        
        flash[:notice] = "Inspection completed. Parts coordinator notified for parts that need ordering."
      end

      redirect_to vmcott_inspector_inspection_path(@inspection)
    end
  rescue ActiveRecord::RecordInvalid => e
    flash[:alert] = "Error saving inspection: #{e.message}"
    render :new_inspection, status: :unprocessable_entity
  rescue => e
    Rails.logger.error "Unexpected error in create_inspection: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    flash[:alert] = "An unexpected error occurred: #{e.message}"
    redirect_to vmcott_inspector_dashboard_path
  end

  def show_inspection
    # @inspection is set by before_action
    # Preload associations for the view
    @inspection = Inspection.includes(
      :vehicle,
      :inspector,
      :final_inspector,
      inspection_jobs: [:job_template, :inspection_job_parts],
      parts_requests: [:part]
    ).find(params[:id])
  end

  def qc_inspection
    # @inspection is set by before_action
    # Preload for QC view
    @inspection = Inspection.includes(
      :vehicle,
      inspection_jobs: [:job_template, :inspection_job_parts]
    ).find(params[:id])
    
    @vehicle = @inspection.vehicle
    @completed_jobs = @inspection.inspection_jobs.where.not(completed_at: nil)
  end

  def complete_qc
    # @inspection is set by before_action
    
    if params[:qc_passed] == 'true'
      @inspection.update!(
        status: 'ready_for_pickup',
        final_inspector_id: current_user.id,
        final_inspection_notes: params[:final_notes],
        final_inspection_completed_at: Time.current,
        ready_for_pickup_at: Time.current,
        notes: @inspection.notes.to_s + "\n\nQC Passed: #{params[:final_notes]}"
      )
      
      # Notify billing/finance team to create invoice
      @inspection.notify_billing_team! if @inspection.respond_to?(:notify_billing_team!)
      
      redirect_to vmcott_inspector_dashboard_path, notice: "QC passed. Vehicle ready for pickup."
    else
      # QC Failed - send back to mechanics
      failure_reason = params[:failure_reason] || "Quality control failed"
      @inspection.update!(
        notes: @inspection.notes.to_s + "\n\nQC Failed: #{failure_reason}",
        status: 'in_progress'
      )
      
      # Reassign to original mechanic if exists
      if @inspection.inspection_jobs.any?
        @inspection.inspection_jobs.each do |job|
          if job.assigned_mechanic.present?
            # Notify mechanic
            Rails.logger.info "QC Failed - Notifying mechanic #{job.assigned_mechanic.name} for job #{job.id}"
          end
        end
      end
      
      redirect_to vmcott_inspector_dashboard_path, alert: "QC failed - work order reopened for fixes."
    end
  rescue => e
    Rails.logger.error "Error in complete_qc: #{e.message}"
    flash[:alert] = "Error completing QC: #{e.message}"
    redirect_to vmcott_inspector_inspection_path(@inspection)
  end

  private

  def set_inspection
    @inspection = Inspection.includes(
      :vehicle, 
      :inspector, 
      :final_inspector,
      inspection_jobs: [:job_template, :inspection_job_parts],
      parts_requests: [:part]
    ).find_by(id: params[:id])
    
    if @inspection.nil?
      flash[:alert] = "Inspection not found"
      redirect_to vmcott_inspector_dashboard_path and return false
    end
  end

  def require_inspector
    unless current_user.inspector? || current_user.maintenance_supervisor? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Inspector privileges required."
    end
  end
end