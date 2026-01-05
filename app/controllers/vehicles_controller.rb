# app/controllers/vehicles_controller.rb
class VehiclesController < ApplicationController
  include Pundit::Authorization  # Ensure Pundit is included here too
  
  before_action :authenticate_user!
  before_action :set_vehicle, only: [:show, :edit, :update, :destroy, :full_details, :mark_maintenance_completed, :report_issue, :trips, :track_live, :tracking_history]

  # ====================================================
  # RBAC AUTHORIZATION SETUP
  # ====================================================
  after_action :verify_authorized, except: [:index, :analytics, :maintenance_dashboard, :export_csv, :themes]
  after_action :verify_policy_scoped, only: [:index, :analytics, :maintenance_dashboard]

  # ====================================================
  # List all vehicles (WITH RBAC and fallback)
  # ====================================================
  def index
    # Try to use Pundit policy scope with fallback
    begin
      @vehicles = policy_scope(Vehicle).includes(:driver, primary_photo_attachment: { blob: :variant_records })
    rescue NoMethodError => e
      # Fallback if Pundit isn't working
      Rails.logger.warn "Pundit policy_scope failed, using manual filtering: #{e.message}"
      
      if current_user.system_admin?
        @vehicles = Vehicle.all
      elsif current_user.agency
        @vehicles = Vehicle.where(agency_id: current_user.agency_id)
      else
        @vehicles = Vehicle.none
      end
      
      @vehicles = @vehicles.includes(:driver, primary_photo_attachment: { blob: :variant_records })
    end
    
    # Apply filters
    @query = params[:query]
    @owner_filter = params[:owner].presence && params[:owner] != "All" ? params[:owner] : nil
    
    @vehicles = @vehicles.search(@query) if @query.present?
    @vehicles = @vehicles.where(service_owner: @owner_filter) if @owner_filter.present?
    @vehicles = @vehicles.order(:make, :model)
    
    # Pagination for better performance
    @vehicles = @vehicles.page(params[:page]).per(20)
    
    # Log access (safe version)
    current_user.log_access("vehicles.index", outcome: "granted", details: { 
      query: @query, 
      owner_filter: @owner_filter,
      page: params[:page]
    })
  end

  # ====================================================
  # Vehicle Analytics Dashboard (WITH RBAC and fallback)
  # ====================================================
  def analytics
    # Try to use Pundit policy scope with fallback
    begin
      base_vehicles = policy_scope(Vehicle)
    rescue NoMethodError => e
      Rails.logger.warn "Pundit policy_scope failed in analytics, using manual filtering: #{e.message}"
      
      if current_user.system_admin?
        base_vehicles = Vehicle.all
      elsif current_user.agency
        base_vehicles = Vehicle.where(agency_id: current_user.agency_id)
      else
        base_vehicles = Vehicle.none
      end
    end
    
    # Store all params for view
    @current_params = params.permit(:from, :to, :owner, :view, :sort_by, :sort_order, :page)
    
    @owner_filter = params[:owner].presence && params[:owner] != "All Owners" ? params[:owner] : nil
    @from = params[:from].present? ? Date.parse(params[:from]) : 30.days.ago.to_date
    @to = params[:to].present? ? Date.parse(params[:to]) : Date.today
    @view = params[:view] || 'grid'
    sort_by = params[:sort_by] || 'utilization'
    sort_order = params[:sort_order] || 'desc'

    # Get filtered vehicles
    @vehicles = base_vehicles
    @vehicles = @vehicles.where(service_owner: @owner_filter) if @owner_filter.present?

    # Build vehicle data with stats
    @vehicle_data = @vehicles.map do |vehicle|
      usage = vehicle.usage_stats(from: @from, to: @to)
      {
        id: vehicle.id,
        name: vehicle.display_name,
        registration_number: vehicle.registration_number,
        service_owner: vehicle.service_owner,
        distance_km: usage[:distance_km].to_f,
        hours_plied: usage[:hours_plied].to_f,
        trip_count: usage[:trip_count],
        utilization: usage[:utilization_percent].to_f
      }
    end

    # Remove vehicles with no data for the period
    @vehicle_data = @vehicle_data.reject { |v| v[:distance_km] == 0 && v[:hours_plied] == 0 }

    # SORTING
    case sort_by
    when 'name'
      @vehicle_data.sort_by! { |v| v[:name].downcase }
    when 'owner'
      @vehicle_data.sort_by! { |v| v[:service_owner] || '' }
    when 'distance'
      @vehicle_data.sort_by! { |v| v[:distance_km] }
    when 'hours'
      @vehicle_data.sort_by! { |v| v[:hours_plied] }
    when 'trips'
      @vehicle_data.sort_by! { |v| v[:trip_count] }
    else # 'utilization' (default)
      @vehicle_data.sort_by! { |v| v[:utilization] }
    end
    
    @vehicle_data.reverse! if sort_order == 'desc'

    # PAGINATION
    @total_vehicles = @vehicle_data.length
    @per_page = 24
    @page = params[:page]&.to_i || 1
    @total_pages = @total_vehicles > 0 ? (@total_vehicles.to_f / @per_page).ceil : 1
    @page = 1 if @page < 1
    @page = @total_pages if @page > @total_pages && @total_pages > 0
    
    start_index = (@page - 1) * @per_page
    @paginated_vehicles = @vehicle_data[start_index, @per_page] || []

    # STATISTICS
    if @vehicle_data.any?
      total_vehicles = @vehicle_data.length
      utilizations = @vehicle_data.map { |v| v[:utilization] }.reject(&:nan?)
      
      # Calculate stats with better NaN handling
      @stats = {
        total_distance: @vehicle_data.sum { |v| v[:distance_km].to_f.nan? ? 0 : v[:distance_km] }.round(1),
        total_hours: @vehicle_data.sum { |v| v[:hours_plied].to_f.nan? ? 0 : v[:hours_plied] }.round(1),
        total_trips: @vehicle_data.sum { |v| v[:trip_count] },
        avg_utilization: utilizations.any? ? (utilizations.sum / utilizations.size).round(1) : 0,
        high_utilization: @vehicle_data.count { |v| (v[:utilization].to_f.nan? ? 0 : v[:utilization]) >= 70 },
        medium_utilization: @vehicle_data.count { |v| 
          util = v[:utilization].to_f.nan? ? 0 : v[:utilization]
          util >= 30 && util < 70 
        },
        low_utilization: @vehicle_data.count { |v| 
          util = v[:utilization].to_f.nan? ? 0 : v[:utilization]
          util < 30 
        }
      }
    else
      @stats = {
        total_distance: 0,
        total_hours: 0,
        total_trips: 0,
        avg_utilization: 0,
        high_utilization: 0,
        medium_utilization: 0,
        low_utilization: 0
      }
    end

    # OWNER DISTRIBUTION
    @owner_distribution = @vehicle_data.group_by { |v| v[:service_owner] }
                                     .transform_values(&:count)
                                     .sort_by { |owner, count| -count }

    # Log access
    current_user.log_access("vehicles.analytics", outcome: "granted", 
      details: { from: @from, to: @to, owner_filter: @owner_filter, vehicles_count: @vehicle_data.length })

    respond_to do |format|
      format.html
      format.csv do
        # Manual authorization if Pundit fails
        unless current_user.system_admin? || current_user.fleet_manager?
          redirect_to root_path, alert: "You are not authorized to export data."
          return
        end
        
        require 'csv'
        csv_data = CSV.generate(headers: true) do |csv|
          csv << ["Vehicle", "License Plate", "Service Owner", "Distance (km)", "Hours", "Trips", "Utilization %", "Period Days"]
          @vehicle_data.each do |vehicle|
            csv << [
              vehicle[:name],
              vehicle[:registration_number],
              vehicle[:service_owner],
              vehicle[:distance_km].round(1),
              vehicle[:hours_plied].round(1),
              vehicle[:trip_count],
              vehicle[:utilization].round(1),
              (@to - @from + 1).to_i
            ]
          end
        end
        send_data csv_data, filename: "vehicle-analytics-#{Date.today}.csv", type: "text/csv"
      end
    end
  end

  # ====================================================
  # Maintenance Dashboard (WITH RBAC and fallback)
  # ====================================================
  def maintenance_dashboard
    # Try to use Pundit policy scope with fallback
    begin
      @vehicles = policy_scope(Vehicle).includes(:maintenances, :driver, :trips, primary_photo_attachment: { blob: :variant_records })
    rescue NoMethodError => e
      Rails.logger.warn "Pundit policy_scope failed in maintenance_dashboard, using manual filtering: #{e.message}"
      
      if current_user.system_admin?
        @vehicles = Vehicle.all
      elsif current_user.agency
        @vehicles = Vehicle.where(agency_id: current_user.agency_id)
      else
        @vehicles = Vehicle.none
      end
      
      @vehicles = @vehicles.includes(:maintenances, :driver, :trips, primary_photo_attachment: { blob: :variant_records })
    end
    
    @query = params[:query]
    @owner_filter = params[:owner].presence && params[:owner] != "All" ? params[:owner] : nil
    
    @vehicles = @vehicles.where(service_owner: @owner_filter) if @owner_filter.present?
    @vehicles = @vehicles.search(@query) if @query.present?
    
    # Sort vehicles with pending maintenance first
    @vehicles = @vehicles.sort_by do |vehicle|
      has_pending = vehicle.maintenances.any? { |m| m.present? && m.status == "Pending" }
      has_pending ? 0 : 1
    end
    
    @maintenances = @vehicles.flat_map(&:maintenances).compact
    
    # Log access
    current_user.log_access("vehicles.maintenance_dashboard", outcome: "granted", 
      details: { query: @query, owner_filter: @owner_filter, vehicles_count: @vehicles.count })
  end

  # ====================================================
  # Show a single vehicle (WITH RBAC and fallback)
  # ====================================================
  def show
    # Try to authorize with Pundit, fallback to manual check
    begin
      authorize @vehicle
    rescue NoMethodError => e
      Rails.logger.warn "Pundit authorize failed, using manual authorization: #{e.message}"
      
      # Manual authorization
      unless current_user.system_admin? || @vehicle.agency_id == current_user.agency_id
        redirect_to root_path, alert: "You are not authorized to view this vehicle."
        return
      end
    end
    
    @maintenances = @vehicle.maintenances.order(date: :desc).compact
    @current_maintenance = @maintenances.find { |m| m.status == 'Pending' }
    @last_maintenance = @maintenances.first

    if @last_maintenance&.mileage && @vehicle.mileage
      service_interval = 5000
      @next_service_mileage = @last_maintenance.mileage + service_interval
      @mileage_left = @next_service_mileage - @vehicle.mileage
    end

    @driver = @vehicle.driver
    @upcoming_trips = @vehicle.trips.where("start_time >= ?", Time.current).order(:start_time)
    
    # Log access
    current_user.log_access("vehicles.show", @vehicle, outcome: "granted")
  end

  # ====================================================
  # GPS Tracking - Live (WITH RBAC & APPROVAL and fallback)
  # ====================================================
  def track_live
    # Try to authorize with Pundit, fallback to manual check
    begin
      authorize @vehicle, :track_live?
    rescue NoMethodError => e
      Rails.logger.warn "Pundit authorize failed, using manual authorization: #{e.message}"
      
      # Manual authorization
      unless current_user.system_admin? || @vehicle.agency_id == current_user.agency_id
        redirect_to root_path, alert: "You are not authorized to track this vehicle."
        return
      end
      
      # Check additional permissions for tracking
      unless current_user.fleet_manager? || current_user.dispatcher?
        redirect_to root_path, alert: "You need fleet manager or dispatcher permissions for live tracking."
        return
      end
    end
    
    # Check GPS approval for sensitive roles
    if current_user.requires_gps_approval? && !current_user.gps_approved_for?(@vehicle, "live")
      redirect_to new_gps_access_approval_path(vehicle_id: @vehicle.id, access_type: 'live'),
                  alert: "GPS live tracking requires approval for your role."
      return
    end
    
    # Show live tracking interface
    @access_type = 'live'
    
    # Log sensitive access
    current_user.log_access("tracking.live", @vehicle, outcome: "granted",
      details: { access_type: 'live', approved: true })
  end

  # ====================================================
  # GPS Tracking - History (WITH RBAC and fallback)
  # ====================================================
  def tracking_history
    # Try to authorize with Pundit, fallback to manual check
    begin
      authorize @vehicle, :view_history?
    rescue NoMethodError => e
      Rails.logger.warn "Pundit authorize failed, using manual authorization: #{e.message}"
      
      # Manual authorization
      unless current_user.system_admin? || @vehicle.agency_id == current_user.agency_id
        redirect_to root_path, alert: "You are not authorized to view tracking history."
        return
      end
    end
    
    # Check GPS approval for sensitive roles
    if current_user.requires_gps_approval? && !current_user.gps_approved_for?(@vehicle, "history")
      redirect_to new_gps_access_approval_path(vehicle_id: @vehicle.id, access_type: 'history'),
                  alert: "GPS history access requires approval for your role."
      return
    end
    
    # Get tracking history
    @from_date = params[:from].present? ? Date.parse(params[:from]) : 7.days.ago.to_date
    @to_date = params[:to].present? ? Date.parse(params[:to]) : Date.today
    
    # Here you would fetch GPS data for the vehicle
    # @gps_points = @vehicle.gps_points.where(timestamp: @from_date..@to_date).order(:timestamp)
    
    # Log access
    current_user.log_access("tracking.history", @vehicle, outcome: "granted",
      details: { from: @from_date, to: @to_date, approved: true })
  end

  # ====================================================
  # Full vehicle details (WITH RBAC and fallback)
  # ====================================================
  def full_details
    # Try to authorize with Pundit, fallback to manual check
    begin
      authorize @vehicle
    rescue NoMethodError => e
      Rails.logger.warn "Pundit authorize failed, using manual authorization: #{e.message}"
      
      # Manual authorization
      unless current_user.system_admin? || @vehicle.agency_id == current_user.agency_id
        redirect_to root_path, alert: "You are not authorized to view vehicle details."
        return
      end
    end
    
    @maintenances = @vehicle.maintenances.order(date: :desc).compact
    
    # Only eager load documents if the association exists
    if Maintenance.reflect_on_association(:documents)
      @maintenances = @maintenances.includes(:documents)
    end
    
    @documents = @vehicle.vehicle_documents.includes(file_attachment: :blob).order(expires_on: :asc)
    @driver = @vehicle.driver
    @upcoming_trips = @vehicle.trips.where("start_time >= ?", Time.current).order(:start_time)
    
    # Log access
    current_user.log_access("vehicles.full_details", @vehicle, outcome: "granted")
  end

  # ====================================================
  # Vehicle Trips - Shows all trips for a specific vehicle
  # ====================================================
  def trips
    # Try to authorize with Pundit, fallback to manual check
    begin
      authorize @vehicle
    rescue NoMethodError => e
      Rails.logger.warn "Pundit authorize failed, using manual authorization: #{e.message}"
      
      # Manual authorization
      unless current_user.system_admin? || @vehicle.agency_id == current_user.agency_id
        redirect_to root_path, alert: "You are not authorized to view vehicle trips."
        return
      end
    end
    
    # Date filtering
    @from_date = params[:from].present? ? Date.parse(params[:from]) : 30.days.ago.to_date
    @to_date = params[:to].present? ? Date.parse(params[:to]) : Date.today
    
    # Get trips for this vehicle within date range
    @trips = @vehicle.trips
                    .where(start_time: @from_date.beginning_of_day..@to_date.end_of_day)
                    .order(start_time: :desc)
    
    # Filter by status if provided
    if params[:status].present? && params[:status] != "All"
      if params[:status] == "Completed"
        @trips = @trips.where.not(end_time: nil)
      elsif params[:status] == "In Progress"
        @trips = @trips.where(end_time: nil)
      end
    end
    
    # Calculate totals using model class methods
    @total_distance = Trip.total_distance(@trips)
    @total_hours = Trip.total_hours(@trips)
    @total_trips = @trips.count
    @avg_distance = Trip.average_distance(@trips)
    
    # Paginate
    @trips = @trips.page(params[:page]).per(20)
    
    # Log access
    current_user.log_access("vehicles.trips", @vehicle, outcome: "granted",
      details: { from: @from_date, to: @to_date, trips_count: @trips.count })
  end

  # ====================================================
  # CRUD: new, create, edit, update, destroy
  # ====================================================
  def new
    @vehicle = Vehicle.new
    
    # Try to authorize with Pundit, fallback to manual check
    begin
      authorize @vehicle
    rescue NoMethodError => e
      Rails.logger.warn "Pundit authorize failed, using manual authorization: #{e.message}"
      
      # Manual authorization
      unless current_user.system_admin? || current_user.fleet_manager?
        redirect_to root_path, alert: "You are not authorized to create vehicles."
        return
      end
    end
  end

  def create
    @vehicle = Vehicle.new(vehicle_params)
    @vehicle.agency = current_user.primary_agency unless current_user.system_admin?
    
    # Try to authorize with Pundit, fallback to manual check
    begin
      authorize @vehicle
    rescue NoMethodError => e
      Rails.logger.warn "Pundit authorize failed, using manual authorization: #{e.message}"
      
      # Manual authorization
      unless current_user.system_admin? || current_user.fleet_manager?
        redirect_to root_path, alert: "You are not authorized to create vehicles."
        return
      end
    end
    
    if @vehicle.save
      current_user.log_access("vehicles.create", @vehicle, outcome: "granted")
      redirect_to vehicles_path, notice: "Vehicle added successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    # Try to authorize with Pundit, fallback to manual check
    begin
      authorize @vehicle
    rescue NoMethodError => e
      Rails.logger.warn "Pundit authorize failed, using manual authorization: #{e.message}"
      
      # Manual authorization
      unless current_user.system_admin? || (current_user.fleet_manager? && @vehicle.agency_id == current_user.agency_id)
        redirect_to root_path, alert: "You are not authorized to edit this vehicle."
        return
      end
    end
  end

  def update
    # Try to authorize with Pundit, fallback to manual check
    begin
      authorize @vehicle
    rescue NoMethodError => e
      Rails.logger.warn "Pundit authorize failed, using manual authorization: #{e.message}"
      
      # Manual authorization
      unless current_user.system_admin? || (current_user.fleet_manager? && @vehicle.agency_id == current_user.agency_id)
        redirect_to root_path, alert: "You are not authorized to update this vehicle."
        return
      end
    end
    
    # Handle photo removal
    remove_photo = params[:vehicle][:remove_primary_photo] == "1"
    
    if @vehicle.update(vehicle_params)
      # Remove the primary photo if checkbox was checked
      if remove_photo && @vehicle.primary_photo.attached?
        @vehicle.primary_photo.purge
      end
      
      # Remove selected gallery photos
      if params[:remove_gallery_photo_ids].present?
        params[:remove_gallery_photo_ids].each do |photo_id|
          @vehicle.gallery_photos.find_by(id: photo_id)&.purge
        end
      end
      
      current_user.log_access("vehicles.update", @vehicle, outcome: "granted")
      redirect_to vehicles_path, notice: "Vehicle updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    # Try to authorize with Pundit, fallback to manual check
    begin
      authorize @vehicle
    rescue NoMethodError => e
      Rails.logger.warn "Pundit authorize failed, using manual authorization: #{e.message}"
      
      # Manual authorization
      unless current_user.system_admin?
        redirect_to root_path, alert: "You are not authorized to delete vehicles."
        return
      end
    end
    
    @vehicle.destroy
    current_user.log_access("vehicles.destroy", @vehicle, outcome: "granted")
    redirect_to vehicles_path, notice: "Vehicle deleted successfully."
  end

  # ====================================================
  # Report Issue for a vehicle - FIXED
  # ====================================================
  def report_issue
    # Try to authorize with Pundit, fallback to manual check
    begin
      authorize @vehicle, :update?
    rescue NoMethodError => e
      Rails.logger.warn "Pundit authorize failed, using manual authorization: #{e.message}"
      
      # Manual authorization
      unless current_user.system_admin? || current_user.driver? || (current_user.fleet_manager? && @vehicle.agency_id == current_user.agency_id)
        redirect_to root_path, alert: "You are not authorized to report issues."
        return
      end
    end
    
    # Create a new maintenance record with default values for driver reports
    @maintenance = @vehicle.maintenances.new(
      source: 'Driver Report',
      assignment_type: 'stores',        # Must be 'stores' or 'purchasing'
      urgency: 'emergency',             # Must be 'routine', 'scheduled', or 'emergency'
      status: 'Pending',
      start_date: Date.today,
      end_date: Date.today + 3.days,
      date: Date.today,
      service_type: 'Driver Reported Issue',  # Required field
      description: 'Issue reported by driver' # Optional but helpful
    )
    
    current_user.log_access("vehicles.report_issue", @vehicle, outcome: "granted")
    render :report_issue
  end

  # ====================================================
  # Mark maintenance as completed
  # ====================================================
  def mark_maintenance_completed
    # Try to authorize with Pundit, fallback to manual check
    begin
      authorize @vehicle, :update?
    rescue NoMethodError => e
      Rails.logger.warn "Pundit authorize failed, using manual authorization: #{e.message}"
      
      # Manual authorization
      unless current_user.system_admin? || current_user.fleet_manager?
        redirect_to root_path, alert: "You are not authorized to update maintenance."
        return
      end
    end
    
    maintenance = @vehicle.maintenances.find(params[:maintenance_id])
    if maintenance.update(status: "Completed")
      current_user.log_access("maintenance.complete", maintenance, outcome: "granted")
      redirect_back fallback_location: maintenance_dashboard_vehicles_path, notice: "Maintenance marked as completed."
    else
      redirect_back fallback_location: maintenance_dashboard_vehicles_path, alert: "Failed to mark maintenance as completed."
    end
  end

  # ====================================================
  # Export CSV from Analytics
  # ====================================================
  def export_csv
    # Try to authorize with Pundit, fallback to manual check
    begin
      authorize :vehicle, :export_csv?
    rescue NoMethodError => e
      Rails.logger.warn "Pundit authorize failed, using manual authorization: #{e.message}"
      
      # Manual authorization
      unless current_user.system_admin? || current_user.fleet_manager? || current_user.auditor?
        redirect_to root_path, alert: "You are not authorized to export data."
        return
      end
    end
    
    require 'csv'
    
    from = params[:from].present? ? Date.parse(params[:from]) : 30.days.ago.to_date
    to   = params[:to].present?   ? Date.parse(params[:to])   : Date.today
    owner = params[:owner].present? && params[:owner] != "All" ? params[:owner] : nil

    # Get vehicles based on user permissions
    if current_user.system_admin?
      vehicles = Vehicle.all
    elsif current_user.agency
      vehicles = Vehicle.where(agency_id: current_user.agency_id)
    else
      vehicles = Vehicle.none
    end
    
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
          vehicle.service_owner,
          distance_sum.round(1),
          hours_sum.round(1),
          trip_count,
          utilization,
          total_days
        ]
      end
    end

    current_user.log_access("vehicles.export_csv", outcome: "granted", 
      details: { from: from, to: to, owner: owner, vehicles_count: vehicles.count })
    
    send_data csv_data, filename: "vehicle-analytics-#{Date.today}.csv", type: "text/csv"
  end

  def themes
    # This will render app/views/vehicles/themes.html.erb
  end

  private

  def set_vehicle
    # Use manual filtering if Pundit fails
    begin
      @vehicle = policy_scope(Vehicle).includes(
        :driver, 
        :maintenances, 
        :trips,
        primary_photo_attachment: { blob: :variant_records },
        gallery_photos_attachments: { blob: :variant_records }
      ).find(params[:id])
    rescue NoMethodError => e
      Rails.logger.warn "Pundit policy_scope failed in set_vehicle, using manual filtering: #{e.message}"
      
      # Manual filtering
      if current_user.system_admin?
        @vehicle = Vehicle.find(params[:id])
      elsif current_user.agency
        @vehicle = Vehicle.where(agency_id: current_user.agency_id).find(params[:id])
      else
        raise ActiveRecord::RecordNotFound
      end
      
      @vehicle = @vehicle.includes(
        :driver, 
        :maintenances, 
        :trips,
        primary_photo_attachment: { blob: :variant_records },
        gallery_photos_attachments: { blob: :variant_records }
      )
    end
  end

  def vehicle_params
    params.require(:vehicle).permit(
      :make, :model, :vehicle_type, :registration_number, :service_owner,
      :chassis_number, :year_of_manufacture, :serial_number, :color,
      :license_plate, :mileage,
      :engine_number, :fuel_type, :transmission, :body_style, :modifications,
      :driver_id, :agency_id,
      :primary_photo,
      :remove_primary_photo,
      gallery_photos: []
    )
  end
  
  # Helper to build analytics params for links
  def analytics_params(overrides = {})
    default_params = {
      from: params[:from] || 30.days.ago.to_date,
      to: params[:to] || Date.today,
      owner: params[:owner] || "All Owners",
      view: params[:view] || 'grid',
      sort_by: params[:sort_by] || 'utilization',
      sort_order: params[:sort_order] || 'desc',
      page: params[:page] || 1,
      per_page: 24
    }
    
    default_params.merge(overrides).reject { |k, v| v.blank? }
  end
end