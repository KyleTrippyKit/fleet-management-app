class MaintenancesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_vehicle
  before_action :set_maintenance, only: [:show, :edit, :update, :destroy, :mark_completed, :confirm_delete]

  # GET /gantt
  # app/controllers/maintenances_controller.rb
def gantt
    @vehicles = Vehicle.includes(:maintenances, :driver).order(:service_owner, :make)
    
    # Initialize @maintenances for statistics
    @maintenances = Maintenance.includes(:vehicle).where.not(start_date: nil)
    
    @gantt_tasks = []
    today = Date.today
    
    @vehicles.each do |vehicle|
      # Skip vehicles with no maintenance
      next if vehicle.maintenances.empty?
      
      # TIER 1: Vehicle parent task
      @gantt_tasks << {
        id: "vehicle_#{vehicle.id}",
        name: "#{vehicle.make} #{vehicle.model} (#{vehicle.registration_number})",
        start: today.strftime("%Y-%m-%d"),
        end: (today + 90.days).strftime("%Y-%m-%d"), # 90-day view
        parent: 0,
        type: 'vehicle',
        color: '#0d6efd',
        details: {
          service_owner: vehicle.service_owner,
          license_plate: vehicle.license_plate || '',
          current_driver: vehicle.driver&.name || 'Unassigned'
        }
      }
      
      # Group maintenances by time periods
      maintenances = vehicle.maintenances.where.not(start_date: nil).order(:start_date)
      
      # Define time periods
      time_periods = {
        this_week: { name: "📅 This Week", start: today, end: today + 6.days },
        next_week: { name: "📅 Next Week", start: today + 7.days, end: today + 13.days },
        this_month: { name: "📅 This Month", start: today + 14.days, end: today.end_of_month },
        future: { name: "📅 Future", start: today.end_of_month + 1.day, end: today + 90.days }
      }
      
      # TIER 2: Time-based folders
      time_periods.each do |period_key, period|
        # Find maintenances in this time period
        period_maintenances = maintenances.select do |m|
          m.start_date && m.start_date.between?(period[:start], period[:end])
        end
        
        next if period_maintenances.empty?
        
        folder_id = "folder_#{vehicle.id}_#{period_key}"
        
        # Calculate folder dates based on contained maintenances
        folder_start = period_maintenances.map(&:start_date).min
        folder_end = period_maintenances.map { |m| m.gantt_end_date }.max
        
        @gantt_tasks << {
          id: folder_id,
          name: period[:name],
          start: folder_start.strftime("%Y-%m-%d"),
          end: folder_end.strftime("%Y-%m-%d"),
          parent: "vehicle_#{vehicle.id}",
          type: 'folder',
          color: time_period_color(period_key),
          details: {
            count: period_maintenances.count,
            period: period[:name]
          }
        }
        
        # TIER 3: Individual maintenance tasks
        period_maintenances.each do |maintenance|
          @gantt_tasks << {
            id: "maintenance_#{maintenance.id}",
            name: maintenance.service_type.to_s,
            start: maintenance.gantt_start_date.strftime("%Y-%m-%d"),
            end: maintenance.gantt_end_date.strftime("%Y-%m-%d"),
            parent: folder_id,
            type: 'maintenance',
            color: maintenance.gantt_bar_color,
            details: {
              status: maintenance.status,
              technician: maintenance.technician_name,
              cost: maintenance.cost || 0,
              urgency: maintenance.urgency || 'routine'
            }
          }
        end
      end
    end
    
    # Convert to JSON for JavaScript - IMPORTANT: Use .to_json directly
    @gantt_json = @gantt_tasks.to_json
    
    # Get filter data
    @vehicles_for_filter = Vehicle.all.order(:make, :model)
    @service_owners = Vehicle.distinct.pluck(:service_owner).compact
    
    # For statistics section - filter based on params
    if params[:vehicle_id].present?
      @maintenances = @maintenances.where(vehicle_id: params[:vehicle_id])
    end
    
    if params[:status].present? && params[:status] != "All Statuses"
      @maintenances = @maintenances.where(status: params[:status])
    end
    
    if params[:owner].present? && params[:owner] != "All Owners"
      @maintenances = @maintenances.joins(:vehicle).where(vehicles: { service_owner: params[:owner] })
    end
    
    # Also set @processed_maintenances for the table if needed
    @processed_maintenances = @maintenances.order('vehicles.make, vehicles.model, start_date')
    
    render :gantt
  end

  # GET /vehicles/:vehicle_id/maintenances
  def index
    @maintenances = if @vehicle.present?
                      @vehicle.maintenances.order(
                        Arel.sql("
                          CASE status 
                            WHEN 'Pending' THEN 0 
                            WHEN 'Completed' THEN 1 
                            ELSE 2 
                          END ASC,
                          date ASC
                        ")
                      )
                    else
                      Maintenance.includes(:vehicle).order(
                        Arel.sql("
                          CASE status 
                            WHEN 'Pending' THEN 0 
                            WHEN 'Completed' THEN 1 
                            ELSE 2 
                          END ASC,
                          date ASC
                        ")
                      )
                    end
  end

  # GET /vehicles/:vehicle_id/maintenances/:id/confirm_delete
  def confirm_delete
    # Renders a confirmation page before deletion
  end

  # DELETE /vehicles/:vehicle_id/maintenances/:id
  def destroy
    @maintenance.destroy
    redirect_to vehicle_path(@vehicle), notice: "Maintenance record was successfully deleted."
  end

  # PATCH /vehicles/:vehicle_id/maintenances/:id/mark_completed
  def mark_completed
    if @maintenance.update(status: "Completed")
      redirect_to maintenance_dashboard_vehicles_path, notice: "Maintenance marked as completed."
    else
      redirect_to maintenance_dashboard_vehicles_path, alert: "Could not mark maintenance as completed."
    end
  end

  # GET /vehicles/:vehicle_id/maintenances/:id
  def show; end

  # GET /vehicles/:vehicle_id/maintenances/new
  def new
    @maintenance = @vehicle.maintenances.new
    @maintenance.mileage ||= @vehicle.mileage
    @service_providers = ServiceProvider.all
  end

  # POST /vehicles/:vehicle_id/maintenances
  def create
    @maintenance = @vehicle.maintenances.new(maintenance_params)
    @service_providers = ServiceProvider.all
    if @maintenance.save
      MaintenanceMailer.notify_store(@maintenance).deliver_later unless @maintenance.part_in_stock
      redirect_to vehicle_path(@vehicle), notice: "Maintenance record was successfully created."
    else
      flash.now[:alert] = "Please correct the errors below."
      render :new, status: :unprocessable_entity
    end
  end

  # GET /vehicles/:vehicle_id/maintenances/:id/edit
  def edit
    @service_providers = ServiceProvider.all
  end

  # PATCH/PUT /vehicles/:vehicle_id/maintenances/:id
  def update
    @service_providers = ServiceProvider.all
    if @maintenance.update(maintenance_params)
      redirect_to vehicle_path(@vehicle), notice: "Maintenance record was successfully updated."
    else
      flash.now[:alert] = "Please correct the errors below."
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_vehicle
    @vehicle = Vehicle.find_by(id: params[:vehicle_id])
  end

  def set_maintenance
    @maintenance = @vehicle.maintenances.find(params[:id])
  end

  def maintenance_params
    params.require(:maintenance).permit(
      :date, :next_due_date, :reminder_sent_at, :service_type, :cost,
      :notes, :mileage, :status, :assignment_type, :part_in_stock,
      :service_provider_id, :estimated_delivery_date, :source, :start_date,
      :end_date, :category, :urgency
    )
  end

  def time_period_color(period)
    case period
    when :this_week
      '#dc3545' # Red - urgent
    when :next_week
      '#fd7e14' # Orange - soon
    when :this_month
      '#20c997' # Teal - scheduled
    when :future
      '#6c757d' # Grey - future
    else
      '#6c757d'
    end
  end
  
  def maintenance_bar_color(maintenance)
    if maintenance.overdue?
      '#dc3545' # Red for overdue
    elsif maintenance.status == "Completed"
      '#28a745' # Green for completed
    elsif maintenance.urgency == "emergency"
      '#fd7e14' # Orange for emergency
    elsif maintenance.urgency == "scheduled"
      '#0dcaf0' # Teal for scheduled
    else
      '#0d6efd' # Blue for routine/default
    end
  end
  
  # Helper method to check if maintenance is overdue
  def overdue?(maintenance)
    maintenance.status == "Pending" && 
    maintenance.next_due_date.present? && 
    maintenance.next_due_date < Date.today
  end
  helper_method :overdue?
  
  # Helper methods for views
  def get_time_based_folder(start_date)
    diff_days = (start_date - Date.today).to_i
    
    if diff_days <= 7
      "this_week"
    elsif diff_days <= 14
      "next_week"
    elsif diff_days <= 30
      "this_month"
    else
      "future"
    end
  end
  helper_method :get_time_based_folder
  
  def urgency_badge_class(urgency)
    case urgency&.downcase
    when 'emergency'
      'bg-danger'
    when 'high'
      'bg-warning'
    when 'scheduled'
      'bg-info'
    else
      'bg-secondary'
    end
  end
  helper_method :urgency_badge_class
  
  def owner_color(owner)
    # Simple hash-based color assignment
    colors = {
      'Fleet Management' => 'primary',
      'Operations' => 'success',
      'Maintenance' => 'warning',
      'Administration' => 'info',
      'Other' => 'secondary'
    }
    colors[owner] || 'dark'
  end
  helper_method :owner_color
end