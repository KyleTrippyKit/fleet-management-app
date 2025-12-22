class VehicleUsagesController < ApplicationController
  before_action :set_vehicle, only: [:new, :create]

  def index
    # ---------------------------
    # DATE RANGE
    # ---------------------------
    from = params[:from].present? ? Date.parse(params[:from]) : 30.days.ago.to_date
    to   = params[:to].present?   ? Date.parse(params[:to])   : Date.today

    # ---------------------------
    # OWNER FILTER
    # ---------------------------
    owner = params[:owner].present? && params[:owner] != "All" ? params[:owner] : nil

    @vehicles = Vehicle.all
    @vehicles = @vehicles.where(service_owner: owner) if owner

    # ---------------------------
    # Initialize chart and table data
    # ---------------------------
    @vehicle_usages = []
    @chart_data = []   # For vehicle cards

    # ---------------------------
    # Process each vehicle
    # ---------------------------
    @vehicles.each do |vehicle|
      trips = vehicle.trips.where(start_time: from.beginning_of_day..to.end_of_day)

      distance_sum = trips.sum(:distance_km).to_f
      hours_sum    = trips.sum(:duration_hours).to_f
      trip_count   = trips.count

      # Overall utilization
      total_days = (to - from + 1).to_i
      utilization = total_days > 0 ? ((hours_sum / (total_days * 24.0)) * 100).round(1) : 0

      # ---------------------------
      # Add to chart data for vehicle cards
      # ---------------------------
      @chart_data << {
        id: vehicle.id,
        registration_number: vehicle.registration_number,
        make: vehicle.make,
        model: vehicle.model,
        service_owner: vehicle.service_owner,
        trip_count: trip_count,
        distance_km: distance_sum,
        hours_plied: hours_sum,
        utilization: utilization,
        total_days: total_days,
        # For better sorting/filtering
        name: "#{vehicle.make} #{vehicle.model}",
        full_name: "#{vehicle.make} #{vehicle.model} (#{vehicle.registration_number})"
      }
    end

    # ---------------------------
    # SORTING
    # ---------------------------
    sort_by = params[:sort_by] || 'utilization'
    sort_order = params[:sort_order] || 'desc'
    
    case sort_by
    when 'name'
      @chart_data.sort_by! { |v| v[:name].downcase }
    when 'owner'
      @chart_data.sort_by! { |v| v[:service_owner] || '' }
    when 'distance'
      @chart_data.sort_by! { |v| v[:distance_km] }
    when 'hours'
      @chart_data.sort_by! { |v| v[:hours_plied] }
    when 'trips'
      @chart_data.sort_by! { |v| v[:trip_count] }
    else # 'utilization' (default)
      @chart_data.sort_by! { |v| v[:utilization] }
    end
    
    # Reverse if descending order
    @chart_data.reverse! if sort_order == 'desc'

    # ---------------------------
    # PAGINATION - FIXED: Ensure @total_vehicles is never nil
    # ---------------------------
    @page = params[:page]&.to_i || 1
    @per_page = params[:per_page]&.to_i || 24  # 24 vehicles per page
    @total_vehicles = @chart_data.length || 0  # FIX: Ensure it's not nil
    @total_pages = @total_vehicles > 0 ? (@total_vehicles.to_f / @per_page).ceil : 1
    
    # Ensure page is within bounds
    @page = 1 if @page < 1
    @page = @total_pages if @page > @total_pages && @total_pages > 0
    
    # Paginate the data
    start_index = (@page - 1) * @per_page
    @paginated_vehicles = @chart_data[start_index, @per_page] || []

    # ---------------------------
    # VIEW PREFERENCE
    # ---------------------------
    @view = params[:view] || 'grid'
    
    # ---------------------------
    # STATISTICS - FIXED: Handle division by zero
    # ---------------------------
    if @chart_data.any?
      @stats = {
        total_distance: @chart_data.sum { |v| v[:distance_km] }.round(1),
        total_hours: @chart_data.sum { |v| v[:hours_plied] }.round(1),
        total_trips: @chart_data.sum { |v| v[:trip_count] },
        avg_utilization: @total_vehicles > 0 ? (@chart_data.sum { |v| v[:utilization] } / @total_vehicles).round(1) : 0,
        low_utilization: @chart_data.count { |v| v[:utilization] < 30 },
        medium_utilization: @chart_data.count { |v| v[:utilization] >= 30 && v[:utilization] <= 70 },
        high_utilization: @chart_data.count { |v| v[:utilization] > 70 }
      }
    else
      @stats = {
        total_distance: 0,
        total_hours: 0,
        total_trips: 0,
        avg_utilization: 0,
        low_utilization: 0,
        medium_utilization: 0,
        high_utilization: 0
      }
    end

    # ---------------------------
    # OWNER DISTRIBUTION
    # ---------------------------
    @owner_distribution = @chart_data.group_by { |v| v[:service_owner] }
                                     .transform_values(&:count)
                                     .sort_by { |owner, count| -count }
  end

  def new
    @vehicle_usage = @vehicle.trips.new
  end

  def create
    @vehicle_usage = @vehicle.trips.new(trip_params)
    if @vehicle_usage.save
      redirect_to vehicle_vehicle_usages_path(@vehicle), notice: "Trip added."
    else
      render :new
    end
  end

  # ---------------------------
  # EXPORT CSV
  # ---------------------------
  def export_csv
    require 'csv'
    
    from = params[:from].present? ? Date.parse(params[:from]) : 30.days.ago.to_date
    to   = params[:to].present?   ? Date.parse(params[:to])   : Date.today
    owner = params[:owner].present? && params[:owner] != "All" ? params[:owner] : nil

    vehicles = Vehicle.all
    vehicles = vehicles.where(service_owner: owner) if owner

    csv_data = CSV.generate(headers: true) do |csv|
      csv << ["Vehicle", "License Plate", "Service Owner", "Distance (km)", "Hours", "Trips", "Utilization %", "Period Days"]
      
      vehicles.each do |vehicle|
        trips = vehicle.trips.where(start_time: from.beginning_of_day..to.end_of_day)
        distance_sum = trips.sum(:distance_km).to_f
        hours_sum = trips.sum(:duration_hours).to_f
        trip_count = trips.count
        total_days = (to - from + 1).to_i
        utilization = total_days > 0 ? ((hours_sum / (total_days * 24.0)) * 100).round(1) : 0
        
        csv << [
          "#{vehicle.make} #{vehicle.model}",
          vehicle.registration_number,
          vehicle.service_owner || "N/A",
          distance_sum.round(1),
          hours_sum.round(1),
          trip_count,
          utilization,
          total_days
        ]
      end
    end

    send_data csv_data, filename: "vehicle-usage-#{Date.today}.csv", type: "text/csv"
  end

  private

  def set_vehicle
    @vehicle = Vehicle.find_by(id: params[:vehicle_id])
  end

  def trip_params
    params.require(:trip).permit(:start_time, :end_time, :distance_km, :duration_hours, :driver_id)
  end
  
  # ---------------------------
  # HELPER METHODS FOR VIEW
  # ---------------------------
  helper_method :utilization_color, :owner_color, :next_sort_order, :sort_icon,
                :utilization_color_class, :owner_badge_class
  
  def utilization_color(utilization)
    case utilization
    when 0..30 then 'danger'
    when 31..70 then 'warning'
    else 'success'
    end
  end
  
  def owner_color(owner)
    return 'secondary' if owner.blank?
    
    case owner
    when 'PTSC' then 'primary'
    when 'Police' then 'danger'
    when 'Fire Service' then 'warning'
    else 'secondary'
    end
  end
  
  def next_sort_order(current_order)
    current_order == 'asc' ? 'desc' : 'asc'
  end
  
  def sort_icon(sort_by, current_sort_by, current_sort_order)
    return '' unless sort_by == current_sort_by
    current_sort_order == 'asc' ? '↑' : '↓'
  end
  
  # For view compatibility
  def utilization_color_class(utilization)
    utilization_color(utilization)
  end
  
  def owner_badge_class(owner)
    owner_color(owner)
  end
end