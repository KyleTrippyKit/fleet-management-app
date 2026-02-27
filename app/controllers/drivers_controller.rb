# frozen_string_literal: true

class DriversController < ApplicationController
  before_action :authenticate_user!
  before_action :set_driver, only: [:show, :edit, :update, :destroy]

  # ============================================================
  # Driver's own vehicle page (for driver role)
  # GET /drivers/my_vehicle
  # ============================================================
  def my_vehicle
    # For driver role - show their assigned vehicle
    @driver = current_user
    @assigned_vehicle = Vehicle.find_by(driver_id: current_user.id)
    
    if @assigned_vehicle
      redirect_to vehicle_path(@assigned_vehicle)
    else
      # Redirect to driver's home page (driver dashboard) when no vehicle assigned
      if current_user.agency&.code == 'PTSC'
        redirect_to ptsc_driver_dashboard_path, alert: "No vehicle is currently assigned to you."
      else
        redirect_to driver_dashboard_path, alert: "No vehicle is currently assigned to you."
      end
    end
  end

  # ============================================================
  # Driver's trips (for driver role)
  # GET /drivers/my_trips
  # ============================================================
  def my_trips
    @trips = Trip.where(driver_id: current_user.id)
                 .includes(:vehicle)
                 .order(start_time: :desc)
                 .page(params[:page]).per(10)
  end

  # ============================================================
  # New issue report (for driver role)
  # GET /drivers/new_issue
  # ============================================================
  def new_issue
    @driver = current_user
    @vehicles = Vehicle.where(driver_id: current_user.id)
    
    # If no vehicles assigned, redirect to dashboard with message
    if @vehicles.empty?
      if current_user.agency&.code == 'PTSC'
        redirect_to ptsc_driver_dashboard_path, alert: "You don't have any assigned vehicles to report issues for."
      else
        redirect_to driver_dashboard_path, alert: "You don't have any assigned vehicles to report issues for."
      end
    end
  end

  # ============================================================
  # Create issue report (for driver role)
  # POST /drivers/create_issue
  # ============================================================
  def create_issue
    @driver = current_user
    vehicle = Vehicle.find_by(id: params[:vehicle_id], driver_id: current_user.id)
    
    if vehicle.nil?
      redirect_to new_issue_drivers_path, alert: "You can only report issues for your assigned vehicles."
      return
    end

    # Create alert for the issue
    alert = Alert.new(
      title: params[:title],
      description: params[:description],
      severity: params[:severity] || "medium",
      priority: params[:priority] || "medium",
      status: "active",
      alert_type: "driver_issue",
      vehicle_id: vehicle.id,
      driver_id: current_user.id,
      agency_id: vehicle.agency_id,
      created_by: current_user.name || current_user.email,
      location: vehicle.current_location
    )

    if alert.save
      redirect_to my_vehicle_drivers_path, notice: "Issue reported successfully. Maintenance has been notified."
    else
      @vehicles = Vehicle.where(driver_id: current_user.id)
      flash.now[:alert] = "Failed to report issue: #{alert.errors.full_messages.join(', ')}"
      render :new_issue, status: :unprocessable_entity
    end
  end

  # ============================================================
  # ✅ Driver JSON Search for Alerts modal/autocomplete
  # GET /drivers/search?q=xxx
  # (accepts q, term, query, search)
  # Returns a SIMPLE array so it matches your vehicles endpoint
  # ============================================================
  def search
    term =
      params[:q].presence ||
      params[:term].presence ||
      params[:query].presence ||
      params[:search].presence

    term = term.to_s.strip

    rel = Driver.all

    if term.present?
      q = "%#{term}%"
      rel = rel.where(
        "drivers.name ILIKE :q OR drivers.license_number ILIKE :q OR drivers.employee_id ILIKE :q OR drivers.contact_number ILIKE :q",
        q: q
      )
    end

    rel = rel.order(:name).limit(25)

    render json: rel.map { |d|
      {
        id: d.id,
        label: "#{d.name} • #{d.employee_id.presence || 'No ID'} • #{d.contact_number}",
        name: d.name,
        employee_id: d.employee_id,
        license_number: d.license_number,
        contact_number: d.contact_number,
        status: d.status
      }
    }
  rescue StandardError => e
    Rails.logger.error("[drivers#search] #{e.class}: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}")
    render json: { error: "Driver search failed" }, status: :internal_server_error
  end

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

  def show
    @trips = @driver.trips
                    .includes(:vehicle)
                    .order(start_time: :desc)
                    .page(params[:trip_page]).per(10)

    @assigned_vehicles = @driver.vehicles || []

    # Maintenance stats - without damage reports
    @maintenance_stats = {
      reports_submitted: 0,
      open_issues: 0,
      resolved_issues: 0
    }

    # Performance metrics
    @performance_metrics = {
      avg_response_time_hours: 0
    }

    # Damage reports - disabled since table doesn't exist
    @damage_reports = []
  end

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

  def edit; end

  def update
    if @driver.update(driver_params)
      redirect_to drivers_path, notice: "Driver updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @driver.trips.exists? || @driver.vehicles.exists?
      redirect_to drivers_path, alert: "Cannot delete driver with trips or assigned vehicles."
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