class VehiclesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_vehicle, only: [:show, :edit, :update, :destroy, :full_details, :mark_maintenance_completed]

  # ====================================================
  # List all vehicles
  # ====================================================
  def index
    @query = params[:query]
    @owner_filter = params[:owner].presence && params[:owner] != "All" ? params[:owner] : nil

    @vehicles = Vehicle.all.includes(:driver) # Include drivers for display efficiency
    @vehicles = @vehicles.search(@query) if @query.present?
    @vehicles = @vehicles.where(service_owner: @owner_filter) if @owner_filter.present?
    @vehicles = @vehicles.order(:make, :model)
  end

  # ====================================================
  # Vehicle Analytics Dashboard
  # ====================================================
  def analytics
    @owner_filter = params[:owner].presence && params[:owner] != "All" ? params[:owner] : nil
    from = params[:from].present? ? Date.parse(params[:from]) : 30.days.ago.to_date
    to = params[:to].present? ? Date.parse(params[:to]) : Date.today

    @vehicles = Vehicle.all.includes(:usage_logs, :driver)
    @vehicles = @vehicles.where(service_owner: @owner_filter) if @owner_filter.present?

    @vehicle_usages = @vehicles.map { |v| v.usage_stats(from: from, to: to) }

    # Prepare chart data
    @chart_data_distance = @vehicle_usages.map { |v| [v[:name], v[:distance_km]] }.presence || [["No Data", 0]]
    @chart_data_hours    = @vehicle_usages.map { |v| [v[:name], v[:hours_plied]] }.presence || [["No Data", 0]]
    @chart_data_util     = @vehicle_usages.map { |v| [v[:name], v[:utilization_percent]] }.presence || [["No Data", 0]]
  end

  # ====================================================
  # Maintenance Dashboard
  # ====================================================
  def maintenance_dashboard
    @query = params[:query]
    @owner_filter = params[:owner].presence && params[:owner] != "All" ? params[:owner] : nil

    @vehicles = Vehicle.all.includes(:maintenances, :driver)
    @vehicles = @vehicles.where(service_owner: @owner_filter) if @owner_filter.present?
    @vehicles = @vehicles.search(@query) if @query.present?

    # Add pending and completed maintenance methods to each vehicle
    @vehicles.each do |vehicle|
      vehicle.define_singleton_method(:pending_maintenances) do
        vehicle.maintenances.where(status: "Pending").order(date: :asc)
      end

      vehicle.define_singleton_method(:completed_maintenances) do
        vehicle.maintenances.where(status: "Completed").order(date: :desc)
      end

      vehicle.define_singleton_method(:overdue_maintenances) do
        vehicle.maintenances.overdue
      end

      # Upcoming trips for this vehicle
      vehicle.define_singleton_method(:upcoming_trips) do
        vehicle.trips.where("start_time >= ?", Time.current).order(:start_time)
      end
    end

    # Sort vehicles: pending maintenance first
    @vehicles = @vehicles.sort_by { |v| v.pending_maintenances.any? ? 0 : 1 }
  end

  # ====================================================
  # Show a single vehicle
  # ====================================================
  def show
    @maintenances = @vehicle.maintenances.order(date: :desc)
    @current_maintenance = @maintenances.find_by(status: 'Pending')
    @last_maintenance = @maintenances.first

    if @last_maintenance&.mileage && @vehicle.mileage
      service_interval = 5000
      @next_service_mileage = @last_maintenance.mileage + service_interval
      @mileage_left = @next_service_mileage - @vehicle.mileage
    end

    # Load driver info for display
    @driver = @vehicle.driver

    # Upcoming trips
    @upcoming_trips = @vehicle.trips.where("start_time >= ?", Time.current).order(:start_time)
  end

  # ====================================================
  # Full vehicle details (for modal or detailed view)
  # ====================================================
  def full_details
    @maintenances = @vehicle.maintenances.order(date: :desc)
    @documents = @vehicle.vehicle_documents.order(expires_on: :asc)
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

  # ====================================================
  # Set vehicle before actions
  # ====================================================
  def set_vehicle
    @vehicle = Vehicle.find(params[:id])
  end

  # ====================================================
  # Strong parameters
  # ====================================================
  def vehicle_params
    params.require(:vehicle).permit(
      :make, :model, :vehicle_type, :registration_number, :service_owner,
      :chassis_number, :year_of_manufacture, :serial_number, :color,
      :license_plate, :mileage, :image, :picture,
      :engine_number, :fuel_type, :transmission, :body_style, :modifications,
      :driver_id,                # <-- allow assigning driver directly
      gallery_images: []
    )
  end

  # ====================================================
  # Gallery image helpers
  # ====================================================
  def attach_gallery_images
    return unless params[:vehicle][:gallery_images].present?
    params[:vehicle][:gallery_images].each { |img| @vehicle.gallery_images.attach(img) }
  end

  def remove_marked_gallery_images
    return unless params[:remove_gallery_image_ids].present?
    params[:remove_gallery_image_ids].each { |id| @vehicle.gallery_images.find_by(id: id)&.purge }
  end
end