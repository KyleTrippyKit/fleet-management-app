class VehiclesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_vehicle, only: [:show, :edit, :update, :destroy, :full_details, :mark_maintenance_completed]

  # ====================================================
  # List all vehicles (FIXED: Added pagination & eager loading)
  # ====================================================
  def index
    @query = params[:query]
    @owner_filter = params[:owner].presence && params[:owner] != "All" ? params[:owner] : nil

    # FIX: Eager load ALL associations used in the index view
    @vehicles = Vehicle.all.includes(:driver, image_attachment: :blob, gallery_images_attachments: :blob)
    
    @vehicles = @vehicles.search(@query) if @query.present?
    @vehicles = @vehicles.where(service_owner: @owner_filter) if @owner_filter.present?
    @vehicles = @vehicles.order(:make, :model)
    
    # ADDED: Pagination for better performance with many records
    @vehicles = @vehicles.page(params[:page]).per(20)
  end

  # ====================================================
  # Vehicle Analytics Dashboard (UPDATED: Added @chart_data)
  # ====================================================
  def analytics
    @owner_filter = params[:owner].presence && params[:owner] != "All" ? params[:owner] : nil
    from = params[:from].present? ? Date.parse(params[:from]) : 30.days.ago.to_date
    to   = params[:to].present?   ? Date.parse(params[:to])   : Date.today

    # FIX: Eager load trips to prevent N+1 in usage_stats method
    @vehicles = Vehicle.all.includes(:trips, :driver, image_attachment: :blob)
    @vehicles = @vehicles.where(service_owner: @owner_filter) if @owner_filter.present?

    # Compute usage stats per vehicle
    @vehicle_usages = @vehicles.map { |v| v.usage_stats(from: from, to: to) }

    # Ensure numeric values to prevent chart "loading"
    @chart_data_distance = @vehicle_usages.map { |v| [v[:name], v[:distance_km] || 0] }
    @chart_data_hours    = @vehicle_usages.map { |v| [v[:name], v[:hours_plied] || 0] }
    @chart_data_util     = @vehicle_usages.map { |v| [v[:name], v[:utilization_percent] || 0] }

    # NEW: Create @chart_data for the Stimulus chart controller
    @chart_data = @vehicle_usages.map do |usage|
      {
        registration_number: usage[:name],
        daily_usage: usage[:daily_usage] || [],  # Use real data if available  # Placeholder - update if you have daily usage data
        trip_count: usage[:trip_count] || 0,
        distance_km: usage[:distance_km] || 0,
        hours_plied: usage[:hours_plied] || 0,
        utilization: usage[:utilization_percent] || 0
      }
    end

    # Fallback if no vehicles
    if @chart_data.empty?
      @chart_data = [{
        registration_number: "No Data",
        daily_usage: [],
        trip_count: 0,
        distance_km: 0,
        hours_plied: 0,
        utilization: 0
      }]
      @chart_data_distance = [["No Data", 0]]
      @chart_data_hours    = [["No Data", 0]]
      @chart_data_util     = [["No Data", 0]]
    end
  end

  # ====================================================
  # Maintenance Dashboard (FIXED: Added eager loading)
  # ====================================================
  def maintenance_dashboard
    @query = params[:query]
    @owner_filter = params[:owner].presence && params[:owner] != "All" ? params[:owner] : nil

    # FIX: Eager load ALL associations used in dashboard
    @vehicles = Vehicle.all.includes(
      :maintenances, 
      :driver, 
      :trips,
      image_attachment: :blob
    )
    
    @vehicles = @vehicles.where(service_owner: @owner_filter) if @owner_filter.present?
    @vehicles = @vehicles.search(@query) if @query.present?

    # Add pending, completed, and overdue methods to each vehicle
    @vehicles.each do |vehicle|
      vehicle.define_singleton_method(:pending_maintenances) do
        # Already preloaded, so this doesn't trigger N+1
        maintenances.select { |m| m.status == "Pending" }.sort_by(&:date)
      end

      vehicle.define_singleton_method(:completed_maintenances) do
        maintenances.select { |m| m.status == "Completed" }.sort_by(&:date).reverse
      end

      vehicle.define_singleton_method(:overdue_maintenances) do
        maintenances.select(&:overdue?)
      end

      vehicle.define_singleton_method(:upcoming_trips) do
        trips.select { |t| t.start_time >= Time.current }.sort_by(&:start_time)
      end
    end

    # Sort vehicles with pending maintenance first
    @vehicles = @vehicles.sort_by { |v| v.pending_maintenances.any? ? 0 : 1 }
  end

  # ====================================================
  # Show a single vehicle (FIXED: Preloaded trips/maintenances)
  # ====================================================
  def show
    # FIX: Use eager loading instead of separate queries
    @maintenances = @vehicle.maintenances.includes(:documents).order(date: :desc)
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
  # Full vehicle details (FIXED: Added eager loading)
  # ====================================================
  def full_details
    # FIX: Preload documents to avoid N+1
    @maintenances = @vehicle.maintenances.includes(:documents).order(date: :desc)
    @documents = @vehicle.vehicle_documents.includes(file_attachment: :blob).order(expires_on: :asc)
    @driver = @vehicle.driver
    @upcoming_trips = @vehicle.trips.where("start_time >= ?", Time.current).order(:start_time)
  end

  # ====================================================
  # CRUD: new, create, edit, update, destroy
  # ====================================================
  def new
    @vehicle = Vehicle.new
  end

  def create
    @vehicle = Vehicle.new(vehicle_params)
    if @vehicle.save
      attach_gallery_images
      redirect_to vehicles_path, notice: "Vehicle added successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @vehicle.update(vehicle_params)
      attach_gallery_images
      remove_marked_gallery_images
      redirect_to vehicles_path, notice: "Vehicle updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @vehicle.destroy
    redirect_to vehicles_path, notice: "Vehicle deleted successfully."
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

  private

  def set_vehicle
    # FIX: Preload common associations when fetching a single vehicle
    @vehicle = Vehicle.includes(
      :driver, 
      :maintenances, 
      :trips,
      image_attachment: :blob,
      gallery_images_attachments: :blob
    ).find(params[:id])
  end

  def vehicle_params
    params.require(:vehicle).permit(
      :make, :model, :vehicle_type, :registration_number, :service_owner,
      :chassis_number, :year_of_manufacture, :serial_number, :color,
      :license_plate, :mileage, :image, :picture,
      :engine_number, :fuel_type, :transmission, :body_style, :modifications,
      :driver_id,
      gallery_images: []
    )
  end

  def attach_gallery_images
    return unless params[:vehicle][:gallery_images].present?
    params[:vehicle][:gallery_images].each { |img| @vehicle.gallery_images.attach(img) }
  end

  def remove_marked_gallery_images
    return unless params[:remove_gallery_image_ids].present?
    params[:remove_gallery_image_ids].each { |id| @vehicle.gallery_images.find_by(id: id)&.purge }
  end
end