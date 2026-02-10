# frozen_string_literal: true

class VehiclesController < ApplicationController
  # Allow unauthenticated access ONLY to catalog_search for autocomplete.
  before_action :authenticate_user!, except: [:catalog_search]

  before_action :set_vehicle, only: [
    :show, :edit, :update, :destroy, :full_details,
    :mark_maintenance_completed, :report_issue, :trips
  ]

  include AgencyStatistics if defined?(AgencyStatistics)

  before_action :set_agency_from_params, only: [:index, :analytics, :maintenance_dashboard]

  before_action :authorize_view!, only: [:show, :full_details, :trips]
  before_action :authorize_edit!, only: [:edit, :update]
  before_action :authorize_create!, only: [:new, :create]
  before_action :authorize_destroy!, only: [:destroy]
  before_action :authorize_report_issue!, only: [:report_issue]
  before_action :authorize_analytics!, only: [:analytics, :export_csv]
  before_action :authorize_maintenance!, only: [:maintenance_dashboard, :mark_maintenance_completed]

  # ============================================
  # Dropdown option lists (for forms)
  # ============================================
  FUEL_TYPES = [
    "Petrol",
    "Diesel",
    "Hybrid (Petrol/Electric)",
    "Hybrid (Diesel/Electric)",
    "Electric",
    "CNG",
    "LPG",
    "Other"
  ].freeze

  TRANSMISSIONS = [
    "Manual",
    "Automatic",
    "CVT",
    "Semi-Automatic"
  ].freeze

  DRIVE_TYPES = [
    "2WD",
    "4WD",
    "AWD",
    "FWD",
    "RWD"
  ].freeze

  # ====================================================
  # ✅ Vehicle JSON Search for Alerts modal/autocomplete
  # GET /vehicles/search?q=xxx
  # ====================================================
  def search
    term = params[:q].presence || params[:term].presence || params[:query].presence
    term = term.to_s.strip

    rel = scoped_vehicles_by_agency
    rel = rel.search(term) if term.present?
    rel = rel.order(updated_at: :desc).limit(25)

    render json: rel.map { |v|
      {
        id: v.id,
        label: "#{v.license_plate} • #{v.make} #{v.model} • #{v.agency&.code}",
        license_plate: v.license_plate,
        registration_number: v.registration_number,
        make: v.make,
        model: v.model,
        agency_id: v.agency_id,
        agency_code: v.agency&.code
      }
    }
  rescue StandardError => e
    Rails.logger.error("[vehicles#search] #{e.class}: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}")
    render json: { error: "Vehicle search failed" }, status: :internal_server_error
  end

  # ====================================================
  # List all vehicles (SIMPLIFIED VERSION)
  # ====================================================
  def index
    @query  = params[:search].presence || params[:query].presence
    @status = params[:status].presence

    # Always agency-scoped
    base = current_user.agency.vehicles

    base = base.search(@query) if @query.present?
    base = base.where(status: @status) if @status.present?

    @vehicles_count  = base.count
    @kpi_active      = base.where(status: "active").count
    @kpi_maintenance = base.where(status: "maintenance").count
    @kpi_out         = base.where(status: ["out", "inactive"]).count

    @vehicles = base.with_attached_primary_photo.with_attached_gallery_photos
                    .order(:make, :model)
                    .page(params[:page]).per(20)
  end

  # ====================================================
  # Vehicle Analytics Dashboard
  # ====================================================
  def analytics
    @current_params = params.permit(:from, :to, :owner, :view, :sort_by, :sort_order, :page, :agency)

    @owner_filter = params[:owner].presence && params[:owner] != "All Owners" ? params[:owner] : nil
    @from = params[:from].present? ? Date.parse(params[:from]) : 30.days.ago.to_date
    @to   = params[:to].present?   ? Date.parse(params[:to])   : Date.today
    @view = params[:view] || "grid"
    sort_by = params[:sort_by] || "utilization"
    sort_order = params[:sort_order] || "desc"

    @vehicles = scoped_vehicles_by_agency
    @vehicles = @vehicles.where(service_owner: @owner_filter) if @owner_filter.present?

    if is_vmcott?
      @agency_filter = params[:agency].presence
      @vehicles = @vehicles.where(agency_id: @agency_filter) if @agency_filter.present?
      @agencies = Agency.all.order(:name)
    end

    @vehicle_data = @vehicles.map do |vehicle|
      usage = vehicle.usage_stats(from: @from, to: @to)
      {
        id: vehicle.id,
        name: vehicle.display_name,
        license_plate: vehicle.license_plate,
        registration_number: vehicle.registration_number,
        service_owner: vehicle.service_owner,
        distance_km: usage[:distance_km].to_f,
        hours_plied: usage[:hours_plied].to_f,
        trip_count: usage[:trip_count],
        utilization: usage[:utilization_percent].to_f,
        agency_name: vehicle.agency&.name || "Unknown Agency",
        agency_code: vehicle.agency&.code || "N/A"
      }
    end

    @vehicle_data = @vehicle_data.reject { |v| v[:distance_km] == 0 && v[:hours_plied] == 0 }

    case sort_by
    when "name"     then @vehicle_data.sort_by! { |v| v[:name].to_s.downcase }
    when "owner"    then @vehicle_data.sort_by! { |v| v[:service_owner].to_s }
    when "agency"   then @vehicle_data.sort_by! { |v| v[:agency_name].to_s }
    when "distance" then @vehicle_data.sort_by! { |v| v[:distance_km].to_f }
    when "hours"    then @vehicle_data.sort_by! { |v| v[:hours_plied].to_f }
    when "trips"    then @vehicle_data.sort_by! { |v| v[:trip_count].to_i }
    else                 @vehicle_data.sort_by! { |v| v[:utilization].to_f }
    end
    @vehicle_data.reverse! if sort_order == "desc"

    @total_vehicles = @vehicle_data.length
    @per_page = 24
    @page = params[:page]&.to_i || 1
    @total_pages = @total_vehicles > 0 ? (@total_vehicles.to_f / @per_page).ceil : 1
    @page = 1 if @page < 1
    @page = @total_pages if @page > @total_pages && @total_pages > 0

    start_index = (@page - 1) * @per_page
    @paginated_vehicles = @vehicle_data[start_index, @per_page] || []

    if @vehicle_data.any?
      utilizations = @vehicle_data.map { |v| v[:utilization].to_f }.reject { |x| x.nan? }
      @stats = {
        total_distance: @vehicle_data.sum { |v| v[:distance_km].to_f.nan? ? 0 : v[:distance_km].to_f }.round(1),
        total_hours:    @vehicle_data.sum { |v| v[:hours_plied].to_f.nan? ? 0 : v[:hours_plied].to_f }.round(1),
        total_trips:    @vehicle_data.sum { |v| v[:trip_count].to_i },
        avg_utilization: utilizations.any? ? (utilizations.sum / utilizations.size).round(1) : 0,
        high_utilization: @vehicle_data.count { |v| (v[:utilization].to_f.nan? ? 0 : v[:utilization].to_f) >= 70 },
        medium_utilization: @vehicle_data.count do |v|
          util = v[:utilization].to_f.nan? ? 0 : v[:utilization].to_f
          util >= 30 && util < 70
        end,
        low_utilization: @vehicle_data.count do |v|
          util = v[:utilization].to_f.nan? ? 0 : v[:utilization].to_f
          util < 30
        end
      }
    else
      @stats = {
        total_distance: 0, total_hours: 0, total_trips: 0, avg_utilization: 0,
        high_utilization: 0, medium_utilization: 0, low_utilization: 0
      }
    end

    @owner_distribution = @vehicle_data.group_by { |v| v[:service_owner] }
                                       .transform_values(&:count)
                                       .sort_by { |_, count| -count }

    if is_vmcott?
      @agency_distribution = @vehicle_data.group_by { |v| v[:agency_name] }
                                          .transform_values(&:count)
                                          .sort_by { |_, count| -count }
    end

    respond_to do |format|
      format.html
      format.csv do
        require "csv"
        csv_data = CSV.generate(headers: true) do |csv|
          headers = ["Vehicle", "License Plate", "Service Owner", "Distance (km)", "Hours", "Trips", "Utilization %", "Period Days"]
          headers << "Agency" if is_vmcott?
          csv << headers

          @vehicle_data.each do |vehicle|
            row = [
              vehicle[:name],
              vehicle[:license_plate],
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
  # Maintenance Dashboard (SERVER-SIDE TABS - CLICKABLE)
  # ====================================================
  def maintenance_dashboard
    @query        = params[:search].presence || params[:query].presence
    @owner_filter = params[:owner].presence && params[:owner] != "All Owners" ? params[:owner] : nil

    # NEW: server-side tab selector (instead of bootstrap tabs)
    @priority = params[:priority].presence_in(%w[overdue pending upcoming completed]) || "overdue"

    @vehicles = scoped_vehicles_by_agency
    @vehicles = @vehicles.where(service_owner: @owner_filter) if @owner_filter.present?
    @vehicles = @vehicles.search(@query) if @query.present?

    if is_vmcott?
      @agency_filter = params[:agency].presence
      @vehicles = @vehicles.where(agency_id: @agency_filter) if @agency_filter.present?
      @agencies = Agency.all.order(:name)
    end

    @vehicles = @vehicles.includes(:maintenances)

    @vehicles = @vehicles.sort_by do |vehicle|
      has_pending = vehicle.maintenances.any? { |m| m.present? && m.status == "Pending" }
      has_pending ? 0 : 1
    end

    @count_overdue   = @vehicles.sum { |v| v.overdue_maintenances.count }
    @count_pending   = @vehicles.sum { |v| v.active_maintenances.count }
    @count_upcoming  = @vehicles.sum { |v| v.upcoming_maintenances.count }
    @count_completed = @vehicles.sum { |v| v.completed_maintenances.count }

    @overdue_vehicles   = @vehicles.select { |v| v.overdue_maintenances.any? }
    @pending_vehicles   = @vehicles.select { |v| v.active_maintenances.any? }
    @upcoming_vehicles  = @vehicles.select { |v| v.upcoming_maintenances.any? }
    @completed_vehicles = @vehicles.select { |v| v.completed_maintenances.any? }

    @maintenances = @vehicles.flat_map(&:maintenances).compact
  end

  # ====================================================
  # Catalog search endpoint (JSON)
  # PUBLIC so autocomplete works without login.
  # ====================================================
  def catalog_search
    q = params[:q].presence || params[:term].presence || params[:query].presence
    q = q.to_s.strip
    render(json: []) and return if q.blank?
    render(json: []) and return unless defined?(VehicleCatalogEntry)

    q_norm = q.gsub(/\s+/, " ").strip
    parts = q_norm.split(" ", 2)
    make_guess  = parts[0].to_s.strip
    model_guess = parts.length > 1 ? parts[1].to_s.strip : ""

    rel = VehicleCatalogEntry.all

    exact = if make_guess.present? && model_guess.present?
      rel.where("LOWER(make) = ? AND LOWER(model) = ?", make_guess.downcase, model_guess.downcase)
    else
      VehicleCatalogEntry.none
    end

    partial = rel.where(
      "make ILIKE :q OR model ILIKE :q OR (make || ' ' || model) ILIKE :q",
      q: "%#{q_norm}%"
    )

    rows = VehicleCatalogEntry
      .from("(#{exact.to_sql} UNION #{partial.to_sql}) vehicle_catalog_entries")
      .select("vehicle_catalog_entries.*")
      .order(:make, :model)
      .limit(30)

    render json: rows.map { |e|
      {
        label: "#{e.make} #{e.model}",
        make: e.make,
        model: e.model,
        vehicle_type: e.vehicle_type
      }
    }
  rescue StandardError
    render json: []
  end

  # ====================================================
  # Show / Details / Trips
  # ====================================================
  def show
    @maintenances = @vehicle.maintenances.order(date: :desc).compact
    @current_maintenance = @maintenances.find { |m| m.status == "Pending" }
    @last_maintenance = @maintenances.first

    if @last_maintenance&.mileage && @vehicle.mileage
      service_interval = 5000
      @next_service_mileage = @last_maintenance.mileage + service_interval
      @mileage_left = @next_service_mileage - @vehicle.mileage
    end

    @driver = @vehicle.driver
    @upcoming_trips = @vehicle.trips.where("start_time >= ?", Time.current).order(:start_time)
  end

  def full_details
    @maintenances = @vehicle.maintenances.order(date: :desc).compact
    @maintenances = @maintenances.includes(:documents) if Maintenance.reflect_on_association(:documents)

    @documents = @vehicle.vehicle_documents.includes(file_attachment: :blob).order(expires_on: :asc)
    @driver = @vehicle.driver
    @upcoming_trips = @vehicle.trips.where("start_time >= ?", Time.current).order(:start_time)
  end

  def trips
    @from_date = params[:from].present? ? Date.parse(params[:from]) : 30.days.ago.to_date
    @to_date = params[:to].present? ? Date.parse(params[:to]) : Date.today

    @trips = @vehicle.trips
                    .where(start_time: @from_date.beginning_of_day..@to_date.end_of_day)
                    .order(start_time: :desc)

    if params[:status].present? && params[:status] != "All"
      if params[:status] == "Completed"
        @trips = @trips.where.not(end_time: nil)
      elsif params[:status] == "In Progress"
        @trips = @trips.where(end_time: nil)
      end
    end

    @total_distance = Trip.total_distance(@trips)
    @total_hours = Trip.total_hours(@trips)
    @total_trips = @trips.count
    @avg_distance = Trip.average_distance(@trips)

    @trips = @trips.page(params[:page]).per(20)
  end

  # ====================================================
  # CRUD
  # ====================================================
  def new
    @vehicle = Vehicle.new
    @vehicle.agency = current_user.agency unless is_vmcott?
    @agencies = Agency.all.order(:name) if is_vmcott?
    @vehicle_types = vehicle_types_for_select
  end

  def create
    @vehicle = Vehicle.new(vehicle_params)

    apply_ui_vehicle_fields!(@vehicle)
    enforce_agency_and_owner!(@vehicle)

    if @vehicle.save
      redirect_to vehicles_path, notice: "Vehicle added successfully."
    else
      @agencies = Agency.all.order(:name) if is_vmcott?
      @vehicle_types = vehicle_types_for_select
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @agencies = Agency.all.order(:name) if is_vmcott?
    @vehicle_types = vehicle_types_for_select
  end

  def update
    remove_photo = params.dig(:vehicle, :remove_primary_photo) == "1"

    @vehicle.assign_attributes(vehicle_params)
    apply_ui_vehicle_fields!(@vehicle)
    enforce_agency_and_owner!(@vehicle)

    if @vehicle.save
      @vehicle.primary_photo.purge if remove_photo && @vehicle.primary_photo.attached?

      if params[:remove_gallery_photo_ids].present?
        params[:remove_gallery_photo_ids].each do |photo_id|
          @vehicle.gallery_photos.find_by(id: photo_id)&.purge
        end
      end

      redirect_to vehicles_path, notice: "Vehicle updated successfully."
    else
      @agencies = Agency.all.order(:name) if is_vmcott?
      @vehicle_types = vehicle_types_for_select
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @vehicle.destroy
    redirect_to vehicles_path, notice: "Vehicle deleted successfully."
  end

  # ====================================================
  # Report Issue / Maintenance actions
  # ====================================================
  def report_issue
    @maintenance = @vehicle.maintenances.new(
      source: "Driver Report",
      assignment_type: "stores",
      urgency: "emergency",
      status: "Pending",
      start_date: Date.today,
      end_date: Date.today + 3.days,
      date: Date.today,
      service_type: "Driver Reported Issue",
      description: "Issue reported by driver"
    )
    render :report_issue
  end

  def mark_maintenance_completed
    maintenance = @vehicle.maintenances.find(params[:maintenance_id])
    if maintenance.update(status: "Completed")
      redirect_back fallback_location: maintenance_dashboard_vehicles_path, notice: "Maintenance marked as completed."
    else
      redirect_back fallback_location: maintenance_dashboard_vehicles_path, alert: "Failed to mark maintenance as completed."
    end
  end

  # ====================================================
  # Export CSV
  # ====================================================
  def export_csv
    require "csv"

    from = params[:from].present? ? Date.parse(params[:from]) : 30.days.ago.to_date
    to   = params[:to].present?   ? Date.parse(params[:to])   : Date.today
    owner = params[:owner].present? && params[:owner] != "All" ? params[:owner] : nil
    agency = params[:agency].presence

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
        hours_sum    = trips.sum(:duration_hours).to_f
        trip_count   = trips.count
        total_days   = (to - from + 1).to_i
        utilization  = total_days > 0 ? ((hours_sum / (total_days * 24.0)) * 100).round(1) : 0

        row = [
          "#{vehicle.make} #{vehicle.model}",
          vehicle.license_plate,
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
    # renders app/views/vehicles/themes.html.erb
  end

  private

  # ====================================================
  # Record loading
  # ====================================================
  def set_vehicle
    @vehicle = Vehicle.includes(
      :agency, :driver, :maintenances, :trips,
      primary_photo_attachment: { blob: :variant_records },
      gallery_photos_attachments: { blob: :variant_records }
    ).find(params[:id])
  end

  # ====================================================
  # Strong params
  # ====================================================
  def vehicle_params
    params.require(:vehicle).permit(
      :make, :model, :vehicle_type, :registration_number, :service_owner,
      :chassis_number, :year_of_manufacture, :serial_number, :color,
      :license_plate, :mileage,
      :engine_number, :fuel_type, :transmission, :body_style, :modifications,
      :agency_id,
      :primary_photo,
      :remove_primary_photo,
      :make_model_ui,
      :license_registration_ui,
      gallery_photos: []
    )
  end

  # ====================================================
  # UI-only field parsing (ROBUST + NO "model blank" FAILS)
  # ====================================================
  def apply_ui_vehicle_fields!(vehicle)
    raw = params[:vehicle]
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    raw ||= {}

    mm = raw["make_model_ui"].to_s.strip
    if mm.present?
      mm = mm.gsub(/\s+/, " ").strip
      parts = mm.split(" ", 2)
      make_part  = parts[0].to_s.strip
      model_part = parts.length > 1 ? parts[1].to_s.strip : ""

      vehicle.make  = make_part if make_part.present?

      if model_part.present?
        vehicle.model = model_part
      else
        vehicle.model = vehicle.model.presence || "Unknown"
      end
    end

    vehicle.make  = raw["make"].to_s.strip if vehicle.make.blank? && raw["make"].present?
    vehicle.model = raw["model"].to_s.strip if vehicle.model.blank? && raw["model"].present?

    vehicle.model = "Unknown" if vehicle.model.blank? && vehicle.make.present?

    lr = raw["license_registration_ui"].to_s.strip
    if lr.present?
      normalized = lr.gsub(/\s+/, " ").strip
      chunks = normalized.split(%r{[/\-|,]}, 2).map(&:strip).reject(&:blank?)
      plate = chunks[0].to_s
      reg   = chunks.length > 1 ? chunks[1].to_s : ""

      vehicle.license_plate       = plate if plate.present?
      vehicle.registration_number = reg   if reg.present?
    end

    if vehicle.vehicle_type.blank? && vehicle.make.present? && vehicle.model.present? && defined?(VehicleCatalogEntry)
      entry = VehicleCatalogEntry
        .where("LOWER(make) = ? AND LOWER(model) = ?", vehicle.make.downcase, vehicle.model.downcase)
        .first
      vehicle.vehicle_type = entry.vehicle_type if entry&.vehicle_type.present?
    end

    vehicle.vehicle_type = "Other" if vehicle.vehicle_type.blank?
  end

  # ====================================================
  # Enforce agency + service_owner rules
  # ====================================================
  def enforce_agency_and_owner!(vehicle)
    if is_vmcott?
      vehicle.agency ||= current_user.agency
      vehicle.agency_id ||= vehicle.agency&.id
      if vehicle.respond_to?(:service_owner=) && vehicle.agency&.code.present?
        vehicle.service_owner = vehicle.agency.code
      end
    else
      vehicle.agency = current_user.agency
      vehicle.agency_id = current_user.agency_id
      if vehicle.respond_to?(:service_owner=) && current_user.agency&.code.present?
        vehicle.service_owner = current_user.agency.code
      end
    end
  end

  # ====================================================
  # Vehicle type select list (catalog + fallbacks)
  # ====================================================
  def vehicle_types_for_select
    types = []
    if defined?(VehicleCatalogEntry)
      types = VehicleCatalogEntry.distinct.order(:vehicle_type).pluck(:vehicle_type).compact
    end
    fallback = ["Patrol Vehicle", "Bus", "Mini Bus", "SUV", "Pickup", "Van", "Truck", "Motorcycle", "Other"]
    (types + fallback).map(&:to_s).map(&:strip).reject(&:blank?).uniq
  end

  # ====================================================
  # Agency scoping - FIXED: No params[:id] usage
  # ====================================================
  def set_agency_from_params
    agency_id = params[:agency_id].presence || params[:agency].presence
    @selected_agency = Agency.find_by(id: agency_id) if agency_id.present?

    if @selected_agency && !is_vmcott? && @selected_agency != current_user.agency
      redirect_to vehicles_path, alert: "You can only view your own agency's vehicles."
    end
  end

  def scoped_vehicles_by_agency
    if @selected_agency
      @selected_agency.vehicles.with_attached_primary_photo.with_attached_gallery_photos
    elsif is_vmcott?
      Vehicle.all.with_attached_primary_photo.with_attached_gallery_photos
    else
      current_user.agency.vehicles.with_attached_primary_photo.with_attached_gallery_photos
    end
  end

  # ====================================================
  # Permission Service Authorization Methods
  # ====================================================
  def authorize_view!
    permission = PermissionService.new(current_user, @vehicle)
    redirect_to vehicles_path, alert: "You are not authorized to view this vehicle." unless permission.can?(:view_vehicle)
  end

  def authorize_edit!
    permission = PermissionService.new(current_user, @vehicle)
    redirect_to vehicles_path, alert: "You are not authorized to edit this vehicle." unless permission.can?(:edit_vehicle)
  end

  def authorize_create!
    unless current_user.fleet_manager? || current_user.admin? || current_user.manager?
      redirect_to vehicles_path, alert: "You are not authorized to add new vehicles."
    end
  end

  def authorize_destroy!
    permission = PermissionService.new(current_user, @vehicle)
    redirect_to vehicles_path, alert: "You are not authorized to delete this vehicle." unless permission.can?(:delete_vehicle)
  end

  def authorize_report_issue!
    unless current_user.driver? || current_user.maintenance_supervisor? ||
           current_user.fleet_manager? || current_user.admin?
      redirect_to vehicles_path, alert: "You are not authorized to report issues."
    end
  end

  def authorize_analytics!
    unless current_user.can_see_financial_data? || current_user.fleet_manager? || current_user.manager?
      redirect_to vehicles_path, alert: "You are not authorized to view analytics."
    end
  end

  def authorize_maintenance!
    unless current_user.can_see_maintenance_data? || current_user.fleet_manager? || current_user.admin?
      redirect_to vehicles_path, alert: "You are not authorized to view maintenance data."
    end
  end

  # ====================================================
  # Role helper (FIXED)
  # ====================================================
  def is_vmcott?
    current_user&.agency&.code.to_s.downcase == "vmcott"
  end
end
