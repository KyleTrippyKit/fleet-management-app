class MaintenancesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_vehicle, except: [:gantt]
  before_action :set_maintenance, only: [:show, :edit, :update, :destroy, :mark_completed, :confirm_delete]

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
    Rails.logger.info "Gantt tasks prepared: #{@gantt_tasks&.count || 0}"
    Rails.logger.info "Vehicle tasks: #{@gantt_tasks&.count { |t| t[:type] == 'vehicle' } || 0}"
    Rails.logger.info "Maintenance tasks: #{@gantt_tasks&.count { |t| t[:type] == 'maintenance' } || 0}"
    
    # Set up filter options
    @service_owners = Vehicle.distinct.pluck(:service_owner).compact
    @vehicles_for_filter = Vehicle.all.order(:make, :model)
    @processed_maintenances = @maintenances

    # Debug logging
    if @maintenances.any?
      Rails.logger.info "Sample maintenance data:"
      @maintenances.first(3).each do |m|
        Rails.logger.info "  - #{m.vehicle&.make} #{m.vehicle&.model}: #{m.service_type} (#{m.start_date} to #{m.end_date})"
      end
    end

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

    if params[:owner].present? && params[:owner] != "All Owners"
      maintenances = maintenances.joins(:vehicle)
                                 .where(vehicles: { service_owner: params[:owner] })
    end

    filter_by_date_range(maintenances)
  end

  def filter_by_date_range(maintenances)
    if params[:date_range].present?
      if params[:date_range] == "custom" && params[:start_date].present? && params[:end_date].present?
        start_date = Date.parse(params[:start_date])
        end_date = Date.parse(params[:end_date])
        maintenances = maintenances.where('start_date <= ? AND end_date >= ?', end_date, start_date)
      elsif params[:date_range] != "custom"
        days = params[:date_range].to_i
        end_date = Date.today + days.days
        maintenances = maintenances.where('end_date >= ? AND start_date <= ?', Date.today, end_date)
      end
    else
      end_date = Date.today + 90.days
      maintenances = maintenances.where('end_date >= ? AND start_date <= ?', Date.today, end_date)
    end

    maintenances
  end

  def prepare_gantt_data(maintenances)
    @gantt_tasks = []
    return if maintenances.empty?

    Rails.logger.info "=== PREPARING GANTT DATA ==="
    Rails.logger.info "Processing #{maintenances.count} maintenances"
    
    # Group maintenances by vehicle
    vehicles_grouped = maintenances.group_by(&:vehicle)
    Rails.logger.info "Grouped into #{vehicles_grouped.keys.compact.count} vehicles"
    
    vehicles_grouped.each do |vehicle, vehicle_maintenances|
      next unless vehicle && vehicle_maintenances.any?
      
      Rails.logger.info "Processing vehicle: #{vehicle.id} - #{vehicle.make} #{vehicle.model}"
      Rails.logger.info "  Has #{vehicle_maintenances.count} maintenances"
      
      # Find min start date and max end date for this vehicle
      start_dates = vehicle_maintenances.map(&:start_date).compact
      end_dates = vehicle_maintenances.map(&:end_date).compact
      
      next if start_dates.empty? || end_dates.empty?
      
      vehicle_start = start_dates.min
      vehicle_end = end_dates.max
      
      Rails.logger.info "  Vehicle date range: #{vehicle_start} to #{vehicle_end}"
      
      # Vehicle task
      @gantt_tasks << {
        id: "vehicle_#{vehicle.id}",
        name: "#{vehicle.make} #{vehicle.model} (#{vehicle.registration_number})",
        start: vehicle_start.to_time.to_i * 1000,
        end: vehicle_end.to_time.to_i * 1000,
        parent: "0",
        type: 'vehicle',
        color: '#6c757d',
        details: {
          service_owner: vehicle.service_owner,
          registration_number: vehicle.registration_number,
          current_driver: vehicle.driver&.name || 'Unassigned'
        }
      }
      
      # Maintenance tasks for this vehicle
      vehicle_maintenances.each_with_index do |maintenance, index|
        next unless maintenance.start_date && maintenance.end_date
        
        Rails.logger.info "  Adding maintenance #{index + 1}: #{maintenance.service_type}"
        Rails.logger.info "    Dates: #{maintenance.start_date} to #{maintenance.end_date}"
        Rails.logger.info "    Status: #{maintenance.status}, Urgency: #{maintenance.urgency}"
        
        @gantt_tasks << {
          id: "maintenance_#{maintenance.id}",
          name: maintenance.service_type.to_s.presence || "Maintenance ##{maintenance.id}",
          start: maintenance.start_date.to_time.to_i * 1000,
          end: maintenance.end_date.to_time.to_i * 1000,
          parent: "vehicle_#{vehicle.id}",
          type: 'maintenance',
          color: maintenance.gantt_bar_color || 'rgba(108, 117, 125, 0.8)',
          details: {
            status: maintenance.status || 'Pending',
            urgency: maintenance.urgency || 'Normal',
            cost: maintenance.cost.to_f || 0,
            notes: maintenance.notes.to_s,
            vehicle_id: vehicle.id,
            maintenance_id: maintenance.id,
            duration: maintenance.duration_days
          }
        }
      end
    end

    @gantt_json = @gantt_tasks.to_json
    Rails.logger.info "=== GANTT DATA PREPARED ==="
    Rails.logger.info "Total tasks generated: #{@gantt_tasks.count}"
    Rails.logger.info "Vehicle tasks: #{@gantt_tasks.count { |t| t[:type] == 'vehicle' }}"
    Rails.logger.info "Maintenance tasks: #{@gantt_tasks.count { |t| t[:type] == 'maintenance' }}"
    
    if @gantt_tasks.any?
      Rails.logger.info "Sample data:"
      @gantt_tasks.first(3).each do |task|
        Rails.logger.info "  #{task[:type]}: #{task[:name]}"
        Rails.logger.info "    Start: #{task[:start]} (#{Time.at(task[:start]/1000)})"
        Rails.logger.info "    End: #{task[:end]} (#{Time.at(task[:end]/1000)})"
      end
    end
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