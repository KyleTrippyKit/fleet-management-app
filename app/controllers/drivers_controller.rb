class DriversController < ApplicationController
  before_action :authenticate_user!
  before_action :set_driver, only: [:show, :edit, :update, :destroy]

  # ============================================================
  # List drivers (search + sort + pagination)
  # ============================================================
  def index
    @query = params[:query]
    @sort_column = params[:sort].presence_in(%w[name license_number status]) || "name"
    @sort_direction = params[:direction].presence_in(%w[asc desc]) || "asc"

    @drivers = Driver
                .includes(:assigned_vehicles, :trips, :vehicle_usages)
                .order("#{@sort_column} #{@sort_direction}")

    if @query.present?
      q = "%#{@query}%"
      @drivers = @drivers.where(
        "drivers.name ILIKE ? OR drivers.license_number ILIKE ?",
        q, q
      )
    end

    @drivers = @drivers.page(params[:page]).per(10)

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  # ============================================================
  # Show driver details
  # ============================================================
  def show
    @assigned_vehicles = @driver.assigned_vehicles
    @historical_vehicles = @driver.vehicles

    @trip_sort_column = params[:trip_sort].presence_in(%w[start_time end_time vehicle_id]) || "start_time"
    @trip_sort_direction = params[:trip_direction].presence_in(%w[asc desc]) || "desc"

    @trips = @driver.trips
                    .includes(:vehicle)
                    .order("#{@trip_sort_column} #{@trip_sort_direction}")
                    .page(params[:trip_page]).per(10)
  end

  # ============================================================
  # New / Create
  # ============================================================
  def new
    @driver = Driver.new
  end

  def create
    @driver = Driver.new(driver_params.except(:vehicle_ids))

    if @driver.save
      update_assigned_vehicles
      redirect_to drivers_path, notice: "Driver created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # ============================================================
  # Edit / Update
  # ============================================================
  def edit; end

  def update
    if @driver.update(driver_params.except(:vehicle_ids))
      update_assigned_vehicles
      redirect_to drivers_path, notice: "Driver updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # ============================================================
  # Destroy
  # ============================================================
  def destroy
    if @driver.trips.exists? || @driver.vehicle_usages.exists?
      redirect_to drivers_path,
                  alert: "Cannot delete driver with trips or assigned vehicles."
      return
    end

    @driver.destroy
    redirect_to drivers_path, notice: "Driver deleted successfully."
  end

  private

  def set_driver
    @driver = Driver.find(params[:id])
  end

  def driver_params
    params.require(:driver).permit(
      :name,
      :license_number,
      :phone,
      :status,
      :notes,
      vehicle_ids: []
    )
  end

  def update_assigned_vehicles
    return unless params[:driver][:vehicle_ids]

    @driver.vehicle_usages
           .where.not(vehicle_id: params[:driver][:vehicle_ids])
           .destroy_all

    params[:driver][:vehicle_ids].reject(&:blank?).each do |vid|
      @driver.vehicle_usages.find_or_create_by(vehicle_id: vid) do |vu|
        vu.start_date ||= Time.current
      end
    end
  end
end
