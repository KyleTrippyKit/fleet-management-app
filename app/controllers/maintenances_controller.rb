class MaintenancesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_vehicle, except: [:gantt, :update_gantt]
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
    
    # Set up filter options
    @service_owners = Vehicle.distinct.pluck(:service_owner).compact
    @vehicles_for_filter = Vehicle.all.order(:make, :model)
    @processed_maintenances = @maintenances

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
    redirect_to vehicle_path(@vehicle), notice: "Maintenance record was successfully deleted."
  end

  def mark_completed
    if @maintenance.update(status: "Completed")
      redirect_to maintenance_dashboard_vehicles_path, notice: "Maintenance marked as completed."
    else
      redirect_to maintenance_dashboard_vehicles_path, alert: "Could not mark maintenance as completed."
    end
  end

  def show; end

  def new
    @maintenance = @vehicle.maintenances.new
    @maintenance.mileage ||= @vehicle.mileage
    @service_providers = ServiceProvider.all
    @maintenance.start_date ||= Date.today
    @maintenance.end_date ||= Date.today + 7.days
  end

  def create
    @maintenance = @vehicle.maintenances.new(maintenance_params)
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
      redirect_to vehicle_path(@vehicle), notice: "Maintenance record was successfully created."
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
        redirect_to vehicle_path(@vehicle), notice: "Maintenance record was successfully updated."
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
    @vehicle = Vehicle.find_by(id: params[:vehicle_id])
  end

  def set_maintenance
    @maintenance = if params[:vehicle_id].present?
                     @vehicle.maintenances.find(params[:id])
                   else
                     Maintenance.find(params[:id])
                   end
  end

  def maintenance_params
    params.require(:maintenance).permit(
      :date, :next_due_date, :reminder_sent_at, :service_type, :cost,
      :notes, :mileage, :status, :assignment_type, :part_in_stock,
      :service_provider_id, :estimated_delivery_date, :source, :start_date,
      :end_date, :category, :urgency
    )
  end

  def apply_filters(maintenances)
    if params[:status].present? && params[:status] != "All Statuses"
      if params[:status] == "Overdue"
        maintenances = maintenances.select { |m| m.overdue? }
      else
        maintenances = maintenances.where(status: params[:status])
      end
    end

    if params[:vehicle_id].present?
      maintenances = maintenances.where(vehicle_id: params[:vehicle_id])
    end

    if params[:vehicle_search].present?
      search_term = params[:vehicle_search].downcase
      maintenances = maintenances.joins(:vehicle).where(
        "LOWER(vehicles.registration_number) LIKE :search OR 
         LOWER(vehicles.make) LIKE :search OR 
         LOWER(vehicles.model) LIKE :search OR 
         LOWER(vehicles.service_owner) LIKE :search",
        search: "%#{search_term}%"
      )
    end

    if params[:owner].present? && params[:owner] != "All Owners"
      maintenances = maintenances.joins(:vehicle)
                                 .where(vehicles: { service_owner: params[:owner] })
    end

    filter_by_date_range(maintenances)
  end

  # ENHANCED DATE FILTERING: Includes past, future, and all-time options
  def filter_by_date_range(maintenances)
    if params[:date_range].present?
      case params[:date_range]
      when "all_time"
        # Show ALL data - no date filtering
        return maintenances
        
      when "last_7_days"
        start_date = Date.today - 7.days
        end_date = Date.today
        maintenances = maintenances.where('end_date >= ? AND start_date <= ?', start_date, end_date)
        
      when "last_30_days"
        start_date = Date.today - 30.days
        end_date = Date.today
        maintenances = maintenances.where('end_date >= ? AND start_date <= ?', start_date, end_date)
        
      when "last_3_months"
        start_date = Date.today - 3.months
        end_date = Date.today
        maintenances = maintenances.where('end_date >= ? AND start_date <= ?', start_date, end_date)
        
      when "last_6_months"
        start_date = Date.today - 6.months
        end_date = Date.today
        maintenances = maintenances.where('end_date >= ? AND start_date <= ?', start_date, end_date)
        
      when "last_year"
        start_date = Date.today - 1.year
        end_date = Date.today
        maintenances = maintenances.where('end_date >= ? AND start_date <= ?', start_date, end_date)
        
      when "next_7_days"
        start_date = Date.today
        end_date = Date.today + 7.days
        maintenances = maintenances.where('end_date >= ? AND start_date <= ?', start_date, end_date)
        
      when "next_30_days"
        start_date = Date.today
        end_date = Date.today + 30.days
        maintenances = maintenances.where('end_date >= ? AND start_date <= ?', start_date, end_date)
        
      when "next_3_months"
        start_date = Date.today
        end_date = Date.today + 3.months
        maintenances = maintenances.where('end_date >= ? AND start_date <= ?', start_date, end_date)
        
      when "next_6_months"
        start_date = Date.today
        end_date = Date.today + 6.months
        maintenances = maintenances.where('end_date >= ? AND start_date <= ?', start_date, end_date)
        
      when "next_year"
        start_date = Date.today
        end_date = Date.today + 1.year
        maintenances = maintenances.where('end_date >= ? AND start_date <= ?', start_date, end_date)
        
      when "custom"
        if params[:start_date].present? && params[:end_date].present?
          start_date = Date.parse(params[:start_date])
          end_date = Date.parse(params[:end_date])
          maintenances = maintenances.where('start_date <= ? AND end_date >= ?', end_date, start_date)
        end
        
      # Legacy numeric ranges for backward compatibility
      when "7", "30", "90"
        days = params[:date_range].to_i
        end_date = Date.today + days.days
        maintenances = maintenances.where('end_date >= ? AND start_date <= ?', Date.today, end_date)
      end
    else
      # DEFAULT: Show ALL data (no date filter)
      return maintenances
    end

    maintenances
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
      
      # Vehicle task - FIX: Use string dates
      @gantt_tasks << {
        id: "vehicle_#{vehicle.id}",
        text: "#{vehicle.make} #{vehicle.model} (#{vehicle.registration_number})",
        name: "#{vehicle.make} #{vehicle.model} (#{vehicle.registration_number})",
        start_date: vehicle_start.strftime("%Y-%m-%d %H:%M"),
        end_date: vehicle_end.strftime("%Y-%m-%d %H:%M"),
        parent: "0",
        type: 'vehicle',
        progress: 0,
        open: true,
        color: '#6c757d',
        status: 'Active',
        urgency: 'Normal',
        owner: vehicle.service_owner,
        details: {
          service_owner: vehicle.service_owner,
          registration_number: vehicle.registration_number,
          current_driver: vehicle.driver&.name || 'Unassigned',
          vehicle_type: vehicle.vehicle_type
        }
      }
      
      # Maintenance tasks for this vehicle - FIX: Use string dates
      vehicle_maintenances.each_with_index do |maintenance, index|
        next unless maintenance.start_date && maintenance.end_date
        
        progress = maintenance.completed? ? 1 : 0.5
        
        @gantt_tasks << {
          id: "maintenance_#{maintenance.id}",
          text: maintenance.service_type.to_s.presence || "Maintenance ##{maintenance.id}",
          name: maintenance.service_type.to_s.presence || "Maintenance ##{maintenance.id}",
          start_date: maintenance.start_date.strftime("%Y-%m-%d %H:%M"),
          end_date: maintenance.end_date.strftime("%Y-%m-%d %H:%M"),
          parent: "vehicle_#{vehicle.id}",
          type: 'maintenance',
          progress: progress,
          open: true,
          color: maintenance.gantt_bar_color || 'rgba(108, 117, 125, 0.8)',
          status: maintenance.status || 'Pending',
          urgency: maintenance.urgency || 'Normal',
          overdue: maintenance.overdue?,
          owner: vehicle.service_owner,
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
        
        # Create dependency links between consecutive maintenances
        if index > 0
          prev_maintenance = vehicle_maintenances[index - 1]
          @gantt_links << {
            id: "link_#{prev_maintenance.id}_#{maintenance.id}",
            source: "maintenance_#{prev_maintenance.id}",
            target: "maintenance_#{maintenance.id}",
            type: "0"
          }
        end
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
      vehicles: @maintenances.map(&:vehicle).uniq.count
    }
  end
end