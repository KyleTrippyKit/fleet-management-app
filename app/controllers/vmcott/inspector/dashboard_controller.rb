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
    
    # Automatically looks for: app/views/vmcott/inspector/dashboard/new_inspection.html.erb
  end
  
  def create_inspection
    @inspection = Inspection.new(inspection_params)
    @inspection.inspector = current_user
    @inspection.mileage_at_inspection = @inspection.vehicle.mileage
    
    if @inspection.save
      # Create jobs from selected templates
      if params[:job_template_ids].present? && defined?(JobTemplate)
        JobTemplate.where(id: params[:job_template_ids]).each do |template|
          @inspection.inspection_jobs.create!(
            job_template: template,
            description: template.description,
            estimated_labor_cost: template.total_labor_cost,
            estimated_parts_cost: template.total_parts_cost,
            priority: params[:priority] || 'normal'
          )
        end
      end
      
      # Update vehicle status
      if defined?(VehicleStatus)
        VehicleStatus.create!(
          vehicle: @inspection.vehicle,
          status: 'inspection_complete',
          notes: "Inspection completed by #{current_user.name}",
          current: true
        )
      end
      
      redirect_to vmcott_inspector_dashboard_path, notice: "Inspection complete."
    else
      render :new_inspection
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
          status: 'qc_failed',
          notes: "QC failed: #{params[:failure_reason]}",
          current: true
        )
      end
      
      redirect_to vmcott_inspector_dashboard_path, alert: "QC failed - work order reopened"
    end
  end
  
  private
  
  def require_inspector
    unless current_user.inspector? || current_user.maintenance_supervisor? || current_user.admin?
      redirect_to root_path, alert: "Access denied"
    end
  end
  
  def inspection_params
    params.require(:inspection).permit(:vehicle_id, :notes, :next_service_mileage, :next_service_date)
  end
end