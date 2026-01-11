class VehiclesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_vehicle, only: [:show, :edit, :update, :destroy, :full_details, :mark_maintenance_completed, :report_issue, :trips]
  include AgencyStatistics if defined?(AgencyStatistics)
  
  # New before_action for agency-specific routes
  before_action :set_agency_from_params, only: [:index, :analytics, :maintenance_dashboard]
  
  # Authorization before_actions
  before_action :authorize_view!, only: [:show, :full_details, :trips]
  before_action :authorize_edit!, only: [:edit, :update]
  before_action :authorize_create!, only: [:new, :create]
  before_action :authorize_destroy!, only: [:destroy]
  before_action :authorize_report_issue!, only: [:report_issue]
  before_action :authorize_analytics!, only: [:analytics, :export_csv]
  before_action :authorize_maintenance!, only: [:maintenance_dashboard, :mark_maintenance_completed]

  # ====================================================
  # List all vehicles (OPTIMIZED WITH AGENCY SCOPE)
  # ====================================================
  def index
    @query = params[:query]
    @owner_filter = params[:owner].presence && params[:owner] != "All" ? params[:owner] : nil
    
    # Use scoped vehicles based on agency parameter or user's agency
    @vehicles = scoped_vehicles_by_agency
    
    @vehicles = @vehicles.search(@query) if @query.present?
    @vehicles = @vehicles.where(service_owner: @owner_filter) if @owner_filter.present?
    
    # For VMCOTT users, add agency filter
    if is_vmcott?
      @agency_filter = params[:agency].presence
      @vehicles = @vehicles.where(agency_id: @agency_filter) if @agency_filter.present?
      @agencies = Agency.all.order(:name)
    end
    
    @vehicles = @vehicles.order(:make, :model)
    
    # Pagination for better performance
    @vehicles = @vehicles.page(params[:page]).per(20)
  end

  # ====================================================
  # Vehicle Analytics Dashboard (FIXED WITH AGENCY SCOPE)
  # ====================================================
  def analytics
    # Store all params for view
    @current_params = params.permit(:from, :to, :owner, :view, :sort_by, :sort_order, :page)
    
    @owner_filter = params[:owner].presence && params[:owner] != "All Owners" ? params[:owner] : nil
    @from = params[:from].present? ? Date.parse(params[:from]) : 30.days.ago.to_date
    @to = params[:to].present? ? Date.parse(params[:to]) : Date.today
    @view = params[:view] || 'grid'
    sort_by = params[:sort_by] || 'utilization'
    sort_order = params[:sort_order] || 'desc'

    # Get filtered vehicles based on agency scope
    @vehicles = scoped_vehicles_by_agency
    
    @vehicles = @vehicles.where(service_owner: @owner_filter) if @owner_filter.present?
    
    # For VMCOTT, add agency filter to analytics
    if is_vmcott?
      @agency_filter = params[:agency].presence
      @vehicles = @vehicles.where(agency_id: @agency_filter) if @agency_filter.present?
      @agencies = Agency.all.order(:name)
    end

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
        utilization: usage[:utilization_percent].to_f,
        agency_name: vehicle.agency&.name || 'Unknown Agency',
        agency_code: vehicle.agency&.code || 'N/A'
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
    when 'agency'
      @vehicle_data.sort_by! { |v| v[:agency_name] || '' }
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
    
    # AGENCY DISTRIBUTION (for VMCOTT view)
    if is_vmcott?
      @agency_distribution = @vehicle_data.group_by { |v| v[:agency_name] }
                                        .transform_values(&:count)
                                        .sort_by { |agency, count| -count }
    end

    respond_to do |format|
      format.html
      format.csv do
        require 'csv'
        csv_data = CSV.generate(headers: true) do |csv|
          headers = ["Vehicle", "License Plate", "Service Owner", "Distance (km)", "Hours", "Trips", "Utilization %", "Period Days"]
          headers << "Agency" if is_vmcott?
          csv << headers
          
          @vehicle_data.each do |vehicle|
            row = [
              vehicle[:name],
              vehicle[:registration_number],
              vehicle[:service_owner],
              vehicle[:distance_km].round(1),
              vehicle[:hours_plied].round(1),
              vehicle[:trip_count],
              vehicle[:utilization].round(1),
              (@to - @from + 1).to_i
            ]
            row << vehicle[:agency_name] if is_vmcott?
            csv << row
          end
        end
        send_data csv_data, filename: "vehicle-analytics-#{Date.today}.csv", type: "text/csv"
      end
    end
  end

  # ====================================================
  # Maintenance Dashboard (OPTIMIZED WITH AGENCY SCOPE)
  # ====================================================
  def maintenance_dashboard
    @query = params[:query]
    @owner_filter = params[:owner].presence && params[:owner] != "All" ? params[:owner] : nil

    # Get vehicles based on agency scope
    @vehicles = scoped_vehicles_by_agency
    
    @vehicles = @vehicles.where(service_owner: @owner_filter) if @owner_filter.present?
    @vehicles = @vehicles.search(@query) if @query.present?
    
    # For VMCOTT, add agency filter
    if is_vmcott?
      @agency_filter = params[:agency].presence
      @vehicles = @vehicles.where(agency_id: @agency_filter) if @agency_filter.present?
      @agencies = Agency.all.order(:name)
    end
    
    # Sort vehicles with pending maintenance first
    @vehicles = @vehicles.sort_by do |vehicle|
      has_pending = vehicle.maintenances.any? { |m| m.present? && m.status == "Pending" }
      has_pending ? 0 : 1
    end
    
    @maintenances = @vehicles.flat_map(&:maintenances).compact
  end

  # ====================================================
  # Show a single vehicle (OPTIMIZED)
  # ====================================================
  def show
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
  end

  # ====================================================
  # Full vehicle details (OPTIMIZED)
  # ====================================================
  def full_details
    @maintenances = @vehicle.maintenances.order(date: :desc).compact
    
    # Only eager load documents if the association exists
    if Maintenance.reflect_on_association(:documents)
      @maintenances = @maintenances.includes(:documents)
    end
    
    @documents = @vehicle.vehicle_documents.includes(file_attachment: :blob).order(expires_on: :asc)
    @driver = @vehicle.driver
    @upcoming_trips = @vehicle.trips.where("start_time >= ?", Time.current).order(:start_time)
  end

  # ====================================================
  # Vehicle Trips - Shows all trips for a specific vehicle
  # ====================================================
  def trips
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
  end

  # ====================================================
  # CRUD: new, create, edit, update, destroy
  # ====================================================
  def new
    @vehicle = Vehicle.new
    # Set default agency based on user
    @vehicle.agency = current_user.agency unless is_vmcott?
    
    # For VMCOTT users, show agency selection
    @agencies = Agency.all.order(:name) if is_vmcott?
  end

  def create
    @vehicle = Vehicle.new(vehicle_params)
    
    # Auto-assign agency based on service_owner if not set
    if @vehicle.agency_id.blank?
      @vehicle.agency = assign_agency_by_service_owner(@vehicle.service_owner)
    end
    
    if @vehicle.save
      redirect_to vehicles_path, notice: "Vehicle added successfully."
    else
      # For VMCOTT users, show agency selection
      @agencies = Agency.all.order(:name) if is_vmcott?
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    # For VMCOTT users, show agency selection
    @agencies = Agency.all.order(:name) if is_vmcott?
  end

  def update
    # Handle photo removal
    remove_photo = params[:vehicle][:remove_primary_photo] == "1"
    
    # Auto-assign agency based on service_owner if not set
    if vehicle_params[:agency_id].blank? && vehicle_params[:service_owner].present?
      @vehicle.agency = assign_agency_by_service_owner(vehicle_params[:service_owner])
    end
    
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
      
      redirect_to vehicles_path, notice: "Vehicle updated successfully."
    else
      # For VMCOTT users, show agency selection
      @agencies = Agency.all.order(:name) if is_vmcott?
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @vehicle.destroy
    redirect_to vehicles_path, notice: "Vehicle deleted successfully."
  end

  # ====================================================
  # Report Issue for a vehicle - FIXED
  # ====================================================
  def report_issue
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
    render :report_issue
  end

  # ====================================================
  # Mark maintenance as completed
  # ====================================================
  def mark_maintenance_completed
    maintenance = @vehicle.maintenances.find(params[:maintenance_id])
    if maintenance.update(status: "Completed")
      redirect_back fallback_location: maintenance_dashboard_vehicles_path, notice: "Maintenance marked as completed."
    else
      redirect_back fallback_location: maintenance_dashboard_vehicles_path, alert: "Failed to mark maintenance as completed."
    end
  end

  # ====================================================
  # Export CSV from Analytics
  # ====================================================
  def export_csv
    require 'csv'
    
    from = params[:from].present? ? Date.parse(params[:from]) : 30.days.ago.to_date
    to   = params[:to].present?   ? Date.parse(params[:to])   : Date.today
    owner = params[:owner].present? && params[:owner] != "All" ? params[:owner] : nil
    agency = params[:agency].presence

    # Get vehicles based on agency scope
    vehicles = scoped_vehicles_by_agency
    
    vehicles = vehicles.where(service_owner: owner) if owner.present?
    vehicles = vehicles.where(agency_id: agency) if agency.present? && is_vmcott?

    csv_data = CSV.generate(headers: true) do |csv|
      headers = ["Vehicle", "License Plate", "Service Owner", "Distance (km)", "Hours", "Trips", "Utilization %", "Period Days"]
      headers << "Agency" if is_vmcott?
      csv << headers
      
      vehicles.each do |vehicle|
        trips = vehicle.trips.where(start_time: from.beginning_of_day..to.end_of_day)
        distance_sum = trips.sum(:distance_km).to_f
        hours_sum = trips.sum(:duration_hours).to_f
        trip_count = trips.count
        total_days = (to - from + 1).to_i
        utilization = total_days > 0 ? ((hours_sum / (total_days * 24.0)) * 100).round(1) : 0
        
        row = [
          "#{vehicle.make} #{vehicle.model}",
          vehicle.registration_number,
          vehicle.service_owner,
          distance_sum.round(1),
          hours_sum.round(1),
          trip_count,
          utilization,
          total_days
        ]
        row << vehicle.agency.name if is_vmcott?
        csv << row
      end
    end

    send_data csv_data, filename: "vehicle-analytics-#{Date.today}.csv", type: "text/csv"
  end

  def themes
    # This will render app/views/vehicles/themes.html.erb
  end

  private

  def set_vehicle
    # OPTIMIZED: Include variant records for photos
    @vehicle = Vehicle.includes(
      :agency, :driver, :maintenances, :trips,
      primary_photo_attachment: { blob: :variant_records },
      gallery_photos_attachments: { blob: :variant_records }
    ).find(params[:id])
  end

  def vehicle_params
    params.require(:vehicle).permit(
      :make, :model, :vehicle_type, :registration_number, :service_owner,
      :chassis_number, :year_of_manufacture, :serial_number, :color,
      :license_plate, :mileage,
      :engine_number, :fuel_type, :transmission, :body_style, :modifications,
      :driver_id, :agency_id, # Added agency_id
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
    
    # Add agency filter for VMCOTT
    if is_vmcott?
      default_params[:agency] = params[:agency] || ""
    end
    
    default_params.merge(overrides).reject { |k, v| v.blank? }
  end
  
  # Helper method to assign agency based on service_owner
  def assign_agency_by_service_owner(service_owner)
    case service_owner.to_s.downcase
    when 'ptsc'
      Agency.find_by(code: 'PTSC')
    when 'police'
      Agency.find_by(code: 'TTPS')
    when 'fire service'
      Agency.find_by(code: 'TTDF')
    else
      # Default to VMCOTT for other service owners or unknown
      Agency.find_by(code: 'VMCOTT')
    end
  end
  
  # New method to handle agency from params
  def set_agency_from_params
    if params[:id]  # From agency/:id/vehicles route
      @selected_agency = Agency.find_by(id: params[:id])
      
      # Security check: non-VMCOTT users can only view their own agency
      unless is_vmcott? || (@selected_agency && @selected_agency == current_user.agency)
        redirect_to vehicles_path, alert: "You can only view your own agency's vehicles."
      end
    end
  end
  
  def scoped_vehicles_by_agency
    if @selected_agency
      # Show vehicles for the selected agency
      @selected_agency.vehicles.includes(:agency, :driver, primary_photo_attachment: { blob: :variant_records })
    elsif is_vmcott?
      # VMCOTT sees all vehicles
      Vehicle.all.includes(:agency, :driver, primary_photo_attachment: { blob: :variant_records })
    else
      # Other agencies only see their own vehicles
      current_user.agency.vehicles.includes(:driver, primary_photo_attachment: { blob: :variant_records })
    end
  end
  
  # ====================================================
  # Permission Service Authorization Methods
  # ====================================================
  
  def authorize_view!
    permission = PermissionService.new(current_user, @vehicle)
    unless permission.can?(:view_vehicle)
      redirect_to vehicles_path, alert: "You are not authorized to view this vehicle."
    end
  end
  
  def authorize_edit!
    permission = PermissionService.new(current_user, @vehicle)
    unless permission.can?(:edit_vehicle)
      redirect_to vehicles_path, alert: "You are not authorized to edit this vehicle."
    end
  end
  
  def authorize_create!
    # For create, we need to check if user can create vehicles in general
    unless current_user.fleet_manager? || current_user.admin? || current_user.manager?
      redirect_to vehicles_path, alert: "You are not authorized to add new vehicles."
    end
  end
  
  def authorize_destroy!
    permission = PermissionService.new(current_user, @vehicle)
    unless permission.can?(:delete_vehicle)
      redirect_to vehicles_path, alert: "You are not authorized to delete this vehicle."
    end
  end
  
  def authorize_report_issue!
    # Drivers and maintenance supervisors can report issues
    unless current_user.driver? || current_user.maintenance_supervisor? || 
           current_user.fleet_manager? || current_user.admin?
      redirect_to vehicles_path, alert: "You are not authorized to report issues."
    end
  end
  
  def authorize_analytics!
    # Fleet managers, finance, and admins can view analytics
    unless current_user.can_see_financial_data? || current_user.fleet_manager? || current_user.manager?
      redirect_to vehicles_path, alert: "You are not authorized to view analytics."
    end
  end
  
  def authorize_maintenance!
    # Maintenance supervisors, fleet managers, and admins can view maintenance dashboard
    unless current_user.can_see_maintenance_data? || current_user.fleet_manager? || current_user.admin?
      redirect_to vehicles_path, alert: "You are not authorized to view maintenance data."
    end
  end
end