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
                .includes(:vehicles, :trips)
                .order("#{@sort_column} #{@sort_direction}")

    if @query.present?
      q = "%#{@query}%"
      @drivers = @drivers.where(
        "drivers.name ILIKE ? OR drivers.license_number ILIKE ? OR drivers.employee_id ILIKE ?",
        q, q, q
      )
    end

    @drivers = @drivers.page(params[:page]).per(10)

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  # ============================================================
  # Show driver details - MAINTENANCE FOCUSED
  # ============================================================
  def show
    @trips = @driver.trips
                    .includes(:vehicle)
                    .order(start_time: :desc)
                    .page(params[:trip_page]).per(10)
    
    # Simple assignment tracking
    @assigned_vehicles = @driver.vehicles || []
    
    # Performance metrics for maintenance team
    @maintenance_stats = @driver.maintenance_stats
    @performance_metrics = @driver.maintenance_performance
    
    # Initialize empty arrays for non-existent associations
    @maintenance_requests = []
    @damage_reports = @driver.damage_reports
                             .includes(:vehicle)
                             .order(created_at: :desc)
                             .page(params[:damage_page]).per(5) if @driver.respond_to?(:damage_reports)
  end

  # ============================================================
  # New / Create
  # ============================================================
  def new
    @driver = Driver.new
  end

  def create
    @driver = Driver.new(driver_params)

    if @driver.save
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
    if @driver.update(driver_params)
      redirect_to drivers_path, notice: "Driver updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # ============================================================
  # Destroy
  # ============================================================
  def destroy
    if @driver.trips.exists? || @driver.vehicles.exists?
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
      :employee_id,
      :contact_number,
      :emergency_contact_name,
      :emergency_contact_phone,
      :phone,
      :status,
      :notes,
      vehicle_ids: []
    )
  end
end