# app/controllers/vmcott/inspector/dashboard_controller.rb
class Vmcott::Inspector::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_inspector

  def index
    @pending_inspections = ReceptionLog.where(status: 'checked_in')
                                       .includes(:vehicle)
                                       .order(created_at: :desc)
    @in_progress = Inspection.where(inspector: current_user, status: 'pending_inspection')
    @recent_completed = Inspection.where(inspector: current_user)
                                   .where(status: ['inspection_completed', 'approved_for_repair'])
                                   .order(created_at: :desc)
                                   .limit(5)
  end

  def new_inspection
    @vehicle = Vehicle.find(params[:vehicle_id])
    @inspection = Inspection.new(vehicle: @vehicle, inspector: current_user)
    @job_templates = JobTemplate.for_vehicle(@vehicle).active
  end

  def create_inspection
    @inspection = Inspection.new(
      vehicle_id: params[:vehicle_id],
      inspector: current_user,
      mileage_at_inspection: params[:mileage],
      notes: params[:notes],
      next_service_mileage: params[:next_service_mileage],
      next_service_date: params[:next_service_date],
      status: 'inspection_completed'
    )

    ActiveRecord::Base.transaction do
      @inspection.save!

      # Track if any parts need ordering
      parts_need_ordering = false

      # Process parts from all sources
      if params[:parts].present?
        # Group parts by job
        parts_by_job = params[:parts].group_by { |p| [p[:job_type], p[:job_id]] }
        
        parts_by_job.each do |(job_type, job_id), job_parts|
          # Find or create the job
          job = if job_type == 'template'
                  template = JobTemplate.find(job_id)
                  @inspection.inspection_jobs.find_or_create_by!(
                    job_template: template,
                    description: template.name,
                    priority: 'normal'
                  )
                else
                  # For custom jobs, find by description or create
                  custom_job_data = params[:custom_jobs]&.find { |cj| cj[:temp_id] == job_id }
                  @inspection.inspection_jobs.create!(
                    description: custom_job_data&.[](:description) || "Custom Job",
                    priority: 'normal'
                  )
                end

          # Process each part for this job
          job_parts.each do |part_data|
            quantity = part_data[:quantity].to_i
            is_custom = part_data[:is_custom] == 'true'

            if is_custom
              # Custom part - always needs ordering
              parts_need_ordering = true
              
              # Create inspection job part with custom name
              job.inspection_job_parts.create!(
                custom_part_name: part_data[:custom_name],
                quantity: quantity
              )

              # Create parts request for procurement (REMOVED notes field)
              PartsRequest.create!(
                inspection: @inspection,
                custom_part_name: part_data[:custom_name],
                quantity: quantity,
                status: 'pending'
                # Removed: notes: "Custom part needed for job: #{job.description}"
              )
            else
              # Inventory part
              part = Part.find(part_data[:part_id])
              
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
                  # Removed: notes: "Part is in stock (current stock: #{part.current_stock})"
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
                  # Removed: notes: "Out of stock. Need #{quantity - part.current_stock} more (current stock: #{part.current_stock})"
                )
              end
            end
          end
        end
      end

      # Update vehicle mileage
      @inspection.vehicle.update(mileage: params[:mileage]) if params[:mileage].present?

      # Determine next workflow step based on parts needs
      if parts_need_ordering
        @inspection.notify_parts_coordinator! if @inspection.respond_to?(:notify_parts_coordinator!)
        flash[:notice] = "Inspection completed. Parts coordinator notified for parts that need ordering."
      else
        @inspection.update!(status: 'approved_for_repair')
        @inspection.notify_mechanics! if @inspection.respond_to?(:notify_mechanics!)
        flash[:notice] = "Inspection completed. All parts in stock, mechanics notified."
      end

      redirect_to vmcott_inspector_inspection_path(@inspection)
    rescue ActiveRecord::RecordInvalid => e
      flash[:alert] = "Error saving inspection: #{e.message}"
      render :new_inspection, status: :unprocessable_entity
    end
  end

  def show_inspection
    @inspection = Inspection.includes(
      :vehicle, 
      :inspector, 
      :final_inspector,
      inspection_jobs: [:job_template, :inspection_job_parts],
      parts_requests: [:part]
    ).find(params[:id])
  end

  def qc_inspection
    @inspection = Inspection.find(params[:id])
    @vehicle = @inspection.vehicle
    @completed_jobs = @inspection.inspection_jobs.where.not(completed_at: nil)
  end

  def complete_qc
    @inspection = Inspection.find(params[:id])
    
    if params[:qc_passed] == 'true'
      @inspection.update!(
        status: 'qc_completed',
        final_inspector_id: current_user.id,
        final_inspection_notes: params[:final_notes],
        final_inspection_completed_at: Time.current,
        ready_for_pickup_at: Time.current
      )
      @inspection.update!(status: 'ready_for_pickup')
      
      redirect_to vmcott_inspector_dashboard_path, notice: "QC passed. Vehicle ready for pickup."
    else
      @inspection.update!(
        notes: @inspection.notes.to_s + "\n\nQC Failed: #{params[:failure_reason]}",
        status: 'in_progress'
      )
      redirect_to vmcott_inspector_dashboard_path, alert: "QC failed - work order reopened."
    end
  end

  private

  def require_inspector
    unless current_user.inspector? || current_user.maintenance_supervisor? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Inspector privileges required."
    end
  end
end