# app/controllers/vmcott/mechanic/dashboard_controller.rb
class Vmcott::Mechanic::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_mechanic
  
  def index
    @assigned_jobs = InternalPos.where(assigned_to_id: current_user.id)
                                .where(status: ['pending', 'in_progress'])
                                .includes(purchase_order: :vehicle)
                                .order(priority: :desc, created_at: :asc)
    
    @available_jobs = InternalPos.where(status: 'pending', assigned_to_id: nil)
                                .includes(purchase_order: :vehicle)
                                .order(priority: :desc, created_at: :asc)
    
    @completed_today = InternalPos.where(assigned_to_id: current_user.id)
                                  .where(status: 'completed')
                                  .where('updated_at >= ?', Date.current.beginning_of_day)
                                  .count
    
    @recently_completed = InternalPos.where(assigned_to_id: current_user.id)
                                     .where(status: 'completed')
                                     .order(updated_at: :desc)
                                     .limit(10)
                                     .includes(purchase_order: :vehicle)
    
    @pending_qc = InternalPos.where(status: 'pending')
                            .where("notes LIKE ?", "%QC%")
                            .count
  end
  
  def show_job
    @job = InternalPos.includes(purchase_order: :vehicle).find(params[:id])
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
      if defined?(VehicleStatus) && @job.vehicle.present?
        VehicleStatus.create!(
          vehicle: @job.vehicle,
          status: 'repair_in_progress',
          notes: "Work started by #{current_user.name}",
          created_by: current_user,
          current: true
        )
      end
      
      if @job.purchase_order.present?
        @job.purchase_order.update(vmcott_status: 'work_in_progress')
      end
      
      redirect_to vmcott_mechanic_job_path(@job), notice: "Job started successfully"
    else
      redirect_to vmcott_mechanic_dashboard_path, alert: "Could not start job"
    end
  end
  
  # FIXED: Updated to append to notes instead of using non-existent attribute
  def update_progress
    @job = InternalPos.find(params[:id])
    
    if params[:progress_update].present?
      # Format: [HH:MM] User Name: Progress message
      timestamp = Time.current.strftime('%H:%M')
      new_note = "\n[#{timestamp}] #{current_user.name}: #{params[:progress_update]}"
      
      # Append to existing notes
      @job.notes = @job.notes.to_s + new_note
      
      if @job.save
        redirect_to vmcott_mechanic_job_path(@job), notice: "Progress updated successfully"
      else
        redirect_to vmcott_mechanic_job_path(@job), alert: "Could not update progress"
      end
    else
      redirect_to vmcott_mechanic_job_path(@job), alert: "Progress update cannot be blank"
    end
  end
  
  def request_qc
    @job = InternalPos.find(params[:id])
    
    if @job.update(status: 'completed', completed_at: Time.current)
      if defined?(VehicleStatus) && @job.vehicle.present?
        VehicleStatus.create!(
          vehicle: @job.vehicle,
          status: 'qc_pending',
          notes: "Work completed, awaiting QC inspection",
          created_by: current_user,
          current: true
        )
      end
      
      if @job.purchase_order.present?
        qc_exists = InternalPos.where(purchase_order_id: @job.purchase_order_id)
                              .where("notes LIKE ?", "%QC%")
                              .exists?
        
        unless qc_exists
          InternalPos.create!(
            purchase_order: @job.purchase_order,
            work_order_number: InternalPos.generate_work_order_number,
            status: 'pending',
            priority: 'normal',
            notes: "[Work Section: QC / Inspection]\n[Work Role: QC Inspector]\nQuality inspection required for work order #{@job.work_order_number}",
            created_by: current_user
          )
        end
        
        @job.purchase_order.update(vmcott_status: 'internal_work_completed')
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
      
      # Log parts usage to notes
      @job.notes += "\n[#{Time.current.strftime('%H:%M')}] Used #{quantity}x #{part.name} (Stock: #{part.current_stock + quantity} → #{part.current_stock})"
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