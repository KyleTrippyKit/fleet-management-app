# app/controllers/vmcott/mechanic/dashboard_controller.rb
class Vmcott::Mechanic::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_mechanic
  
  def index
    @assigned_jobs = InternalPos.where(assigned_to_id: current_user.id)
                                .where(status: ['pending', 'in_progress'])
                                .includes(:purchase_order => :vehicle)
    
    @available_jobs = InternalPos.where(status: 'pending', assigned_to_id: nil)
                                .includes(:purchase_order => :vehicle)
                                .order(priority: :desc, created_at: :asc)
    
    @completed_today = InternalPos.where(assigned_to_id: current_user.id)
                                  .where(status: 'completed')
                                  .where('updated_at >= ?', Date.current.beginning_of_day)
                                  .count
    
    # Automatically looks for: app/views/vmcott/mechanic/dashboard/index.html.erb
  end
  
  def show_job
    @job = InternalPos.find(params[:id])
    # Automatically looks for: app/views/vmcott/mechanic/dashboard/show_job.html.erb
  end
  
  def assign_self
    @job = InternalPos.find(params[:id])
    
    if @job.update(assigned_to_id: current_user.id, status: 'pending')
      redirect_to vmcott_mechanic_dashboard_path, notice: "Job assigned to you"
    else
      redirect_to vmcott_mechanic_dashboard_path, alert: "Could not assign job"
    end
  end
  
  def start_job
    @job = InternalPos.find(params[:id])
    
    if @job.update(status: 'in_progress', started_at: Time.current)
      if defined?(VehicleStatus)
        VehicleStatus.create!(
          vehicle: @job.vehicle,
          status: 'repair_in_progress',
          notes: "Work started by #{current_user.name}",
          current: true
        )
      end
      
      redirect_to vmcott_mechanic_job_path(@job), notice: "Job started"
    else
      redirect_to vmcott_mechanic_dashboard_path, alert: "Could not start job"
    end
  end
  
  def update_progress
    @job = InternalPos.find(params[:id])
    
    if @job.update(progress_update: params[:progress_update])
      @job.notes += "\n[#{Time.current.strftime('%H:%M')}] #{current_user.name}: #{params[:progress_update]}"
      @job.save
      
      redirect_to vmcott_mechanic_job_path(@job), notice: "Progress updated"
    else
      redirect_to vmcott_mechanic_job_path(@job), alert: "Could not update progress"
    end
  end
  
  def request_qc
    @job = InternalPos.find(params[:id])
    
    if @job.update(status: 'completed')
      if defined?(VehicleStatus)
        VehicleStatus.create!(
          vehicle: @job.vehicle,
          status: 'qc_pending',
          notes: "Work completed, awaiting QC inspection",
          current: true
        )
      end
      
      if defined?(Notification)
        Notification.create!(
          title: "QC Inspection Required",
          message: "Work completed on #{@job.vehicle.license_plate}",
          link: vmcott_inspector_qc_path(@job),
          recipient_type: 'inspector'
        )
      end
      
      redirect_to vmcott_mechanic_dashboard_path, notice: "QC requested"
    else
      redirect_to vmcott_mechanic_job_path(@job), alert: "Could not request QC"
    end
  end
  
  def log_parts_used
    @job = InternalPos.find(params[:id])
    part = Part.find(params[:part_id])
    quantity = params[:quantity].to_i
    
    if part.current_stock >= quantity
      part.update!(current_stock: part.current_stock - quantity)
      
      @job.notes += "\n[#{Time.current.strftime('%H:%M')}] Used #{quantity}x #{part.name}"
      @job.save
      
      render json: { success: true, message: "Parts logged" }
    else
      render json: { success: false, message: "Insufficient stock" }, status: :unprocessable_entity
    end
  end
  
  private
  
  def require_mechanic
    unless current_user.mechanic? || current_user.maintenance_supervisor? || current_user.admin?
      redirect_to root_path, alert: "Access denied"
    end
  end
end