# frozen_string_literal: true

class DriversController < ApplicationController
  before_action :authenticate_user!
  before_action :set_driver, only: [:show, :edit, :update, :destroy]

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
    @maintenance_stats = @driver.maintenance_stats
    @performance_metrics = @driver.maintenance_performance

    @maintenance_requests = []
    @damage_reports = if @driver.respond_to?(:damage_reports)
      @driver.damage_reports
             .includes(:vehicle)
             .order(created_at: :desc)
             .page(params[:damage_page]).per(5)
    else
      []
    end
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
