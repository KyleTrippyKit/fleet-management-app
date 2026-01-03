class MaintenancesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_vehicle, except: [:gantt, :update_gantt, :new, :create, :index]
  before_action :set_maintenance, only: [:show, :edit, :update, :destroy, :mark_completed, :confirm_delete, :update_gantt]

  # GET /gantt
  def gantt
    Rails.logger.info "=== GANTT CHART DEBUG ==="
    
    # Get all maintenances with dates
    @maintenances = Maintenance.includes(:vehicle)
                               .where.not(start_date: nil)
                               .where.not(end_date: nil)
                               .order(:start_date)
    
    Rails.logger.info "Total maintenances with dates: #{@maintenances.count}"
    
    # Apply filters
    @maintenances = apply_filters(@maintenances)
    Rails.logger.info "After filtering: #{@maintenances.count} maintenances"
    
    # Prepare Gantt data
    prepare_gantt_data(@maintenances)
    
    # Set up filter options - FIXED: Use vehicle's service_owner
    @service_owners = Vehicle.distinct.pluck(:service_owner).compact.sort
    @vehicles_for_filter = Vehicle.all.order(:make, :model)
    @processed_maintenances = @maintenances

    # Calculate statistics
    @overdue_count = @maintenances.select(&:overdue?).count
    @total_cost = @maintenances.sum(:cost).to_f
    @vehicles_count = Vehicle.count
    
    render :gantt
  end

  # PATCH /maintenances/:id/update_gantt
  def update_gantt
    if params[:maintenance].present?
      if @maintenance.update(maintenance_params)
        render json: { 
          success: true, 
          message: "Maintenance updated successfully",
          maintenance: @maintenance.gantt_task_data
        }
      else
        render json: { 
          success: false, 
          errors: @maintenance.errors.full_messages 
        }, status: :unprocessable_entity
      end
    else
      render json: { success: false, errors: ["No data provided"] }, status: :bad_request
    end
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

  def confirm_delete; end

  def destroy
    @maintenance.destroy
    if @vehicle.present?
      redirect_to vehicle_path(@vehicle), notice: "Maintenance record was successfully deleted."
    else
      redirect_to maintenance_dashboard_vehicles_path, notice: "Maintenance record was successfully deleted."
    end
  end

  def mark_completed
    if @maintenance.update(status: "Completed")
      redirect_to maintenance_dashboard_vehicles_path, notice: "Maintenance marked as completed."
    else
      redirect_to maintenance_dashboard_vehicles_path, alert: "Could not mark maintenance as completed."
    end
  end

  def show
    @maintenance = Maintenance.find(params[:id])
    @vehicle = @maintenance.vehicle  # Ensure @vehicle is set
  end

  def new
    # Handle different scenarios for creating maintenance
    
    if params[:vehicle_id].present?
      # Coming from "Report Issue" button or vehicle context
      @vehicle = Vehicle.find(params[:vehicle_id])
      @maintenance = @vehicle.maintenances.new
    elsif params[:id].present?
      # Editing existing maintenance (shouldn't normally hit new with id)
      existing = Maintenance.find(params[:id])
      @vehicle = existing.vehicle
      @maintenance = existing.dup
    else
      # Standalone maintenance creation
      @maintenance = Maintenance.new
    end
    
    # Set default values based on source
    @maintenance.mileage ||= @vehicle&.mileage
    @service_providers = ServiceProvider.all
    
    # Set default dates
    @maintenance.start_date ||= Date.today
    @maintenance.end_date ||= Date.today + 7.days
    
    # Special handling for driver-reported issues
    if params[:source] == 'driver_report'
      @maintenance.source = 'Driver Report'
      @maintenance.urgency = 'high'
      @maintenance.service_type ||= 'Repair'
      @maintenance.notes ||= "Issue reported by driver"
      @maintenance.status = 'Pending'
      
      # You might want to add a flash message for the driver
      flash.now[:info] = "Please describe the issue in detail below. Your report will be reviewed by maintenance staff."
    end
    
    # Set context for the view
    @from_report_issue = (params[:source] == 'driver_report')
  end

  def create
    # Find vehicle if vehicle_id is provided in params
    if params[:vehicle_id].present? && !@vehicle
      @vehicle = Vehicle.find(params[:vehicle_id])
    end
    
    # If no vehicle found, try to get from maintenance params
    if !@vehicle && maintenance_params[:vehicle_id].present?
      @vehicle = Vehicle.find(maintenance_params[:vehicle_id])
    end
    
    if @vehicle
      @maintenance = @vehicle.maintenances.new(maintenance_params)
    else
      @maintenance = Maintenance.new(maintenance_params)
    end
    
    @service_providers = ServiceProvider.all

    if maintenance_params[:start_date].present? && maintenance_params[:end_date].present?
      start_date = Date.parse(maintenance_params[:start_date])
      end_date = Date.parse(maintenance_params[:end_date])
      if end_date < start_date
        @maintenance.errors.add(:end_date, "must be after start date")
      end
    end

    if @maintenance.errors.empty? && @maintenance.save
      MaintenanceMailer.notify_store(@maintenance).deliver_later unless @maintenance.part_in_stock
      if @vehicle
        redirect_to vehicle_path(@vehicle), notice: "Maintenance record was successfully created."
      else
        redirect_to maintenance_dashboard_vehicles_path, notice: "Maintenance record was successfully created."
      end
    else
      flash.now[:alert] = "Please correct the errors below."
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @service_providers = ServiceProvider.all
  end

  def update
    @service_providers = ServiceProvider.all

    if maintenance_params[:start_date].present? && maintenance_params[:end_date].present?
      start_date = Date.parse(maintenance_params[:start_date])
      end_date = Date.parse(maintenance_params[:end_date])
      if end_date < start_date
        @maintenance.errors.add(:end_date, "must be after start date")
      end
    end

    if @maintenance.errors.empty? && @maintenance.update(maintenance_params)
      if request.xhr?
        render json: { success: true, message: "Maintenance updated successfully" }
      else
        if @vehicle
          redirect_to vehicle_path(@vehicle), notice: "Maintenance record was successfully updated."
        else
          redirect_to maintenance_dashboard_vehicles_path, notice: "Maintenance record was successfully updated."
        end
      end
    else
      if request.xhr?
        render json: { success: false, errors: @maintenance.errors.full_messages }, 
               status: :unprocessable_entity
      else
        flash.now[:alert] = "Please correct the errors below."
        render :edit, status: :unprocessable_entity
      end
    end
  end

  private

  def set_vehicle
    # Try to find vehicle from multiple sources
    if params[:vehicle_id].present?
      @vehicle = Vehicle.find_by(id: params[:vehicle_id])
    elsif params[:id].present? && action_name == 'new' # For new action with existing id
      # Already handled in new action
    elsif @maintenance&.vehicle
      @vehicle = @maintenance.vehicle
    end
  end

  def set_maintenance
    @maintenance = Maintenance.find(params[:id])
    # Ensure @vehicle is set from maintenance if not already set
    @vehicle ||= @maintenance.vehicle
  end

  def maintenance_params
    params.require(:maintenance).permit(
      :date, :next_due_date, :reminder_sent_at, :service_type, :cost,
      :notes, :mileage, :status, :assignment_type, :part_in_stock,
      :service_provider_id, :estimated_delivery_date, :source, :start_date,
      :end_date, :category, :urgency, :vehicle_id
      # REMOVED: :owner - no longer needed
    )
  end

  def apply_filters(maintenances)
    # Start with all maintenances
    filtered = maintenances
    
    if params[:status].present? && params[:status] != "All Statuses" && params[:status] != ""
      if params[:status] == "Overdue"
        filtered = filtered.select { |m| m.overdue? }
      else
        filtered = filtered.where(status: params[:status])
      end
    end

    if params[:vehicle_id].present? && params[:vehicle_id] != ""
      filtered = filtered.where(vehicle_id: params[:vehicle_id])
    end

    if params[:vehicle_search].present?
      search_term = params[:vehicle_search].downcase
      filtered = filtered.joins(:vehicle).where(
        "LOWER(vehicles.registration_number) LIKE :search OR 
         LOWER(vehicles.make) LIKE :search OR 
         LOWER(vehicles.model) LIKE :search",
        search: "%#{search_term}%"
      )
    end

    # FIXED: Filter by vehicle's service_owner instead of maintenance owner
    if params[:owner].present? && params[:owner] != "All Owners" && params[:owner] != ""
      filtered = filtered.joins(:vehicle).where(vehicles: { service_owner: params[:owner] })
    end

    filter_by_date_range(filtered)
  end

  # ENHANCED DATE FILTERING: Includes past, future, and all-time options
  def filter_by_date_range(maintenances)
    return maintenances if maintenances.is_a?(Array) || !params[:date_range].present?
    
    filtered = maintenances
    
    case params[:date_range]
    when "all_time"
      # Show ALL data - no date filtering
      return filtered
      
    when "last_7_days"
      start_date = Date.today - 7.days
      end_date = Date.today
      filtered = filtered.where('end_date >= ? AND start_date <= ?', start_date, end_date)
      
    when "last_30_days"
      start_date = Date.today - 30.days
      end_date = Date.today
      filtered = filtered.where('end_date >= ? AND start_date <= ?', start_date, end_date)
      
    when "last_3_months"
      start_date = Date.today - 3.months
      end_date = Date.today
      filtered = filtered.where('end_date >= ? AND start_date <= ?', start_date, end_date)
      
    when "last_6_months"
      start_date = Date.today - 6.months
      end_date = Date.today
      filtered = filtered.where('end_date >= ? AND start_date <= ?', start_date, end_date)
      
    when "last_year"
      start_date = Date.today - 1.year
      end_date = Date.today
      filtered = filtered.where('end_date >= ? AND start_date <= ?', start_date, end_date)
      
    when "next_7_days"
      start_date = Date.today
      end_date = Date.today + 7.days
      filtered = filtered.where('end_date >= ? AND start_date <= ?', start_date, end_date)
      
    when "next_30_days"
      start_date = Date.today
      end_date = Date.today + 30.days
      filtered = filtered.where('end_date >= ? AND start_date <= ?', start_date, end_date)
      
    when "next_3_months"
      start_date = Date.today
      end_date = Date.today + 3.months
      filtered = filtered.where('end_date >= ? AND start_date <= ?', start_date, end_date)
      
    when "next_6_months"
      start_date = Date.today
      end_date = Date.today + 6.months
      filtered = filtered.where('end_date >= ? AND start_date <= ?', start_date, end_date)
      
    when "next_year"
      start_date = Date.today
      end_date = Date.today + 1.year
      filtered = filtered.where('end_date >= ? AND start_date <= ?', start_date, end_date)
      
    when "custom"
      if params[:start_date].present? && params[:end_date].present?
        start_date = Date.parse(params[:start_date])
        end_date = Date.parse(params[:end_date])
        filtered = filtered.where('start_date <= ? AND end_date >= ?', end_date, start_date)
      end
      
    # Legacy numeric ranges for backward compatibility
    when "7", "30", "90"
      days = params[:date_range].to_i
      end_date = Date.today + days.days
      filtered = filtered.where('end_date >= ? AND start_date <= ?', Date.today, end_date)
    end

    filtered
  end

  # FIXED: Properly format dates for Gantt
  def prepare_gantt_data(maintenances)
    @gantt_tasks = []
    @gantt_links = []
    return if maintenances.empty?

    Rails.logger.info "=== PREPARING GANTT DATA ==="
    
    # Group maintenances by vehicle
    vehicles_grouped = maintenances.group_by(&:vehicle)
    
    vehicles_grouped.each do |vehicle, vehicle_maintenances|
      next unless vehicle && vehicle_maintenances.any?
      
      # Find min start date and max end date for this vehicle
      start_dates = vehicle_maintenances.map(&:start_date).compact
      end_dates = vehicle_maintenances.map(&:end_date).compact
      
      next if start_dates.empty? || end_dates.empty?
      
      vehicle_start = start_dates.min
      vehicle_end = end_dates.max
      
      # Vehicle task
      @gantt_tasks << {
        id: "vehicle_#{vehicle.id}",
        text: "#{vehicle.make} #{vehicle.model} (#{vehicle.registration_number})",
        name: "#{vehicle.make} #{vehicle.model} (#{vehicle.registration_number})",
        start_date: vehicle_start.strftime("%Y-%m-%d"),
        end_date: vehicle_end.strftime("%Y-%m-%d"),
        parent: "0",
        type: 'vehicle',
        progress: 0,
        open: true,
        color: '#6c757d',
        status: 'Active',
        urgency: 'Normal',
        details: {
          service_owner: vehicle.service_owner,
          registration_number: vehicle.registration_number,
          current_driver: vehicle.driver&.name || 'Unassigned',
          vehicle_type: vehicle.vehicle_type
        }
      }
      
      # Maintenance tasks for this vehicle
      vehicle_maintenances.each_with_index do |maintenance, index|
        next unless maintenance.start_date && maintenance.end_date
        
        progress = maintenance.status == 'Completed' ? 1 : 0.5
        
        # Determine color based on status
        color = '#ffc107'  # default yellow for pending
        if maintenance.status == 'Completed'
          color = '#198754'  # green
        elsif maintenance.overdue?
          color = '#dc3545'  # red
        end
        
        @gantt_tasks << {
          id: "maintenance_#{maintenance.id}",
          text: maintenance.service_type.to_s.presence || "Maintenance ##{maintenance.id}",
          name: maintenance.service_type.to_s.presence || "Maintenance ##{maintenance.id}",
          start_date: maintenance.start_date.strftime("%Y-%m-%d"),
          end_date: maintenance.end_date.strftime("%Y-%m-%d"),
          parent: "vehicle_#{vehicle.id}",
          type: 'maintenance',
          progress: progress,
          open: true,
          color: color,
          status: maintenance.status || 'Pending',
          urgency: maintenance.urgency || 'Normal',
          overdue: maintenance.overdue?,
          details: {
            status: maintenance.status || 'Pending',
            urgency: maintenance.urgency || 'Normal',
            cost: maintenance.cost.to_f || 0,
            notes: maintenance.notes.to_s,
            vehicle_id: vehicle.id,
            maintenance_id: maintenance.id,
            duration: maintenance.duration_days,
            service_owner: vehicle.service_owner,
            service_type: maintenance.service_type,
            category: maintenance.category
          }
        }
      end
    end

    @gantt_json = { data: @gantt_tasks, links: @gantt_links }.to_json
    Rails.logger.info "Gantt tasks prepared: #{@gantt_tasks.count}"
  end

  helper_method :has_gantt_data?, :gantt_statistics

  def has_gantt_data?
    @gantt_tasks&.any?
  end

  def gantt_statistics
    return {} unless @maintenances.any?

    {
      total_tasks: @maintenances.count,
      pending: @maintenances.where(status: "Pending").count,
      completed: @maintenances.where(status: "Completed").count,
      overdue: @maintenances.select { |m| m.overdue? }.count,
      vehicles: @maintenances.map(&:vehicle).compact.uniq.count
    }
  end
end