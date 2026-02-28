# app/controllers/vmcott/inspector/dashboard_controller.rb
class Vmcott::Inspector::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_inspector
  
  def index
    @pending_inspections = ReceptionLog.pending_inspection.includes(:vehicle) if defined?(ReceptionLog)
    @in_progress = Inspection.where(inspector: current_user, completed_at: nil) if defined?(Inspection)
    @recent_completed = Inspection.where(inspector: current_user)
                                  .where.not(completed_at: nil)
                                  .order(completed_at: :desc)
                                  .limit(5) if defined?(Inspection)
    
    # Automatically looks for: app/views/vmcott/inspector/dashboard/index.html.erb
  end
  
  def new_inspection
    @vehicle = Vehicle.find(params[:vehicle_id])
    @inspection = Inspection.new(vehicle: @vehicle, inspector: current_user)
    @job_templates = JobTemplate.where(agency: current_user.agency).active if defined?(JobTemplate)
    @applicable_templates = JobTemplate.for_vehicle(@vehicle).active if defined?(JobTemplate)
    
    # Automatically looks for: app/views/vmcott/inspector/dashboard/new_inspection.html.erb
  end
  
  def create_inspection
    @inspection = Inspection.new(inspection_params)
    @inspection.inspector = current_user
    @inspection.mileage_at_inspection = params[:mileage] || @inspection.vehicle.mileage
    
    # Set next service recommendations
    @inspection.next_service_mileage = params[:next_service_mileage] if params[:next_service_mileage].present?
    @inspection.next_service_date = params[:next_service_date] if params[:next_service_date].present?
    
    if @inspection.save
      # Create jobs from selected templates
      if params[:job_template_ids].present? && defined?(JobTemplate)
        JobTemplate.where(id: params[:job_template_ids]).each do |template|
          @inspection.inspection_jobs.create!(
            job_template: template,
            description: template.description,
            estimated_labor_cost: template.total_labor_cost,
            estimated_parts_cost: template.total_parts_cost,
            priority: params[:priority] || 'normal',
            notes: "Added from template"
          )
        end
      end
      
      # Create custom jobs
      if params[:custom_jobs].present?
        params[:custom_jobs].each do |job_data|
          next if job_data[:description].blank?
          
          @inspection.inspection_jobs.create!(
            description: job_data[:description],
            estimated_labor_cost: job_data[:estimated_labor_cost].to_f,
            estimated_parts_cost: job_data[:estimated_parts_cost].to_f,
            priority: 'normal'
          )
        end
      end
      
      # Update vehicle status
      if defined?(VehicleStatus)
        VehicleStatus.create!(
          vehicle: @inspection.vehicle,
          created_by: current_user,
          status: 'inspection_complete',
          notes: "Inspection completed by #{current_user.name}",
          current: true
        )
      end
      
      # Update vehicle mileage
      if params[:mileage].present?
        @inspection.vehicle.update(mileage: params[:mileage])
      end
      
      redirect_to vmcott_inspector_inspection_path(@inspection), notice: "Inspection completed successfully."
    else
      render :new_inspection, status: :unprocessable_entity
    end
  end
  
  def show_inspection
    @inspection = Inspection.find(params[:id])
    # Automatically looks for: app/views/vmcott/inspector/dashboard/show_inspection.html.erb
  end
  
  def qc_inspection
    @internal_po = InternalPos.find(params[:id])
    @vehicle = @internal_po.vehicle
    # Automatically looks for: app/views/vmcott/inspector/dashboard/qc_inspection.html.erb
  end
  
  def complete_qc
    @internal_po = InternalPos.find(params[:id])
    
    if params[:qc_passed] == 'true'
      @internal_po.update!(status: 'completed')
      
      if defined?(VehicleStatus)
        VehicleStatus.create!(
          vehicle: @internal_po.vehicle,
          created_by: current_user,
          status: 'qc_passed',
          notes: "QC passed by #{current_user.name}",
          current: true
        )
      end
      
      redirect_to vmcott_inspector_dashboard_path, notice: "QC passed, vehicle ready for pickup"
    else
      @internal_po.update!(status: 'pending')
      if defined?(VehicleStatus)
        VehicleStatus.create!(
          vehicle: @internal_po.vehicle,
          created_by: current_user,
          status: 'qc_failed',
          notes: "QC failed: #{params[:failure_reason]}",
          current: true
        )
      end
      
      redirect_to vmcott_inspector_dashboard_path, alert: "QC failed - work order reopened"
    end
  end
  
  def complete_inspection
    @inspection = Inspection.find(params[:id])
    @inspection.update(completed_at: Time.current)
    
    redirect_to vmcott_inspector_inspection_path(@inspection), notice: "Inspection marked as complete."
  end
  
  def create_po
    @inspection = Inspection.find(params[:id])
    
    if @inspection.purchase_order.present?
      redirect_to vmcott_inspector_inspection_path(@inspection), alert: "Purchase order already exists."
      return
    end
    
    if @inspection.inspection_jobs.empty?
      redirect_to vmcott_inspector_inspection_path(@inspection), alert: "No jobs found to create purchase order."
      return
    end
    
    po = @inspection.create_purchase_order_from_jobs(current_user)
    
    redirect_to purchase_order_path(po), notice: "Purchase order created successfully."
  end
  
  private
  
  def require_inspector
    unless current_user.inspector? || current_user.maintenance_supervisor? || current_user.admin?
      redirect_to root_path, alert: "Access denied"
    end
  end
  
  def inspection_params
    params.permit(:vehicle_id, :notes)
  end
end