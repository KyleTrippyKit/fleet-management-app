# frozen_string_literal: true

class VehiclesController < ApplicationController
  # Public catalog search endpoint should work without login
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
    "Petrol", "Diesel", "Hybrid (Petrol/Electric)", "Hybrid (Diesel/Electric)",
    "Electric", "CNG", "LPG", "Other"
  ].freeze

  TRANSMISSIONS = ["Manual", "Automatic", "CVT", "Semi-Automatic"].freeze
  DRIVE_TYPES   = ["2WD", "4WD", "AWD", "FWD", "RWD"].freeze

  # frozen_string_literal: true

module Scanner
  class VehiclesController < ApplicationController
    before_action :authenticate_user!

    # Optional: restrict to scanner users only
    before_action :require_scanner!

    before_action :set_vehicle

    def show
      # This is your scanner-only view.
      # Add scanner-only data here without affecting VehiclesController#show
      @maintenances = @vehicle.maintenances.order(date: :desc).compact
      @documents = @vehicle.vehicle_documents.order(expires_on: :asc) if @vehicle.respond_to?(:vehicle_documents)
      @driver = @vehicle.driver
    end

    private

    def require_scanner!
      # Adjust these role checks to match your app
      unless current_user&.admin? || current_user&.scanner_role?
        redirect_to scanner_home_path, alert: "You are not authorized to use scanner mode."
      end
    end

    def set_vehicle
      @vehicle = Vehicle.includes(
        :agency, :driver, :maintenances, :trips,
        primary_photo_attachment: { blob: :variant_records },
        gallery_photos_attachments: { blob: :variant_records }
      ).find(params[:id])
    end
  end
end


  # ====================================================
  # List all vehicles (OPTIMIZED WITH AGENCY SCOPE)
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
  # Plate lookup (scanner flow)
  # ====================================================
  def lookup
    plate = normalize_plate(params[:license_plate])

    if plate.blank?
      redirect_to scanner_home_path, alert: "Please enter a license plate."
      return
    end

    scope = Vehicle.all

    # Scanner + Admin can search across agencies
    unless current_user&.admin? || current_user&.scanner_role?
      scope = scope.where(agency_id: current_user.agency_id)
    end

    # Match by normalized plate (removes hyphens/spaces/etc.)
    vehicle = scope.find_by(
      "upper(regexp_replace(license_plate, '[^A-Za-z0-9]', '', 'g')) = ?",
      plate
    )

    if vehicle
      redirect_to scanner_vehicle_path(vehicle)
    else
      redirect_to scanner_home_path, alert: "No vehicle found for plate: #{plate}"
    end
  end

  # ====================================================
  # Maintenance Dashboard
  # ====================================================
  def maintenance_dashboard
    @query = params[:query]
    @owner_filter = params[:owner].presence && params[:owner] != "All" ? params[:owner] : nil

    @vehicles = scoped_vehicles_by_agency
    @vehicles = @vehicles.where(service_owner: @owner_filter) if @owner_filter.present?
    @vehicles = @vehicles.search(@query) if @query.present?

    if is_vmcott?
      @agency_filter = params[:agency].presence
      @vehicles = @vehicles.where(agency_id: @agency_filter) if @agency_filter.present?
      @agencies = Agency.all.order(:name)
    end

    @vehicles = @vehicles.sort_by do |vehicle|
      has_pending = vehicle.maintenances.any? { |m| m.present? && m.status == "Pending" }
      has_pending ? 0 : 1
    end

    @maintenances = @vehicles.flat_map(&:maintenances).compact
  end

  # ====================================================
  # Catalog search endpoint (JSON)
  # PUBLIC so autocomplete works without login.
  #
  # Improvements:
  # - Larger result set (limit 30)
  # - Exact make+model matches first
  # - Also supports searching by make-only / model-only
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

    # Exact match first (make+model)
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
      { label: "#{e.make} #{e.model}", make: e.make, model: e.model, vehicle_type: e.vehicle_type }
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
    @to_date   = params[:to].present? ? Date.parse(params[:to]) : Date.today

    @trips = @vehicle.trips
                    .where(start_time: @from_date.beginning_of_day..@to_date.end_of_day)
                    .order(start_time: :desc)

    if params[:status].present? && params[:status] != "All"
      @trips =
        case params[:status]
        when "Completed"   then @trips.where.not(end_time: nil)
        when "In Progress" then @trips.where(end_time: nil)
        else @trips
        end
    end

    @total_distance = Trip.total_distance(@trips)
    @total_hours    = Trip.total_hours(@trips)
    @total_trips    = @trips.count
    @avg_distance   = Trip.average_distance(@trips)

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
  # Maintenance actions
  # ====================================================
  def maintenance_dashboard
    @query = params[:query]
    @owner_filter = params[:owner].presence && params[:owner] != "All" ? params[:owner] : nil

    @vehicles = scoped_vehicles_by_agency
    @vehicles = @vehicles.where(service_owner: @owner_filter) if @owner_filter.present?
    @vehicles = @vehicles.search(@query) if @query.present?

    if is_vmcott?
      @agency_filter = params[:agency].presence
      @vehicles = @vehicles.where(agency_id: @agency_filter) if @agency_filter.present?
      @agencies = Agency.all.order(:name)
    end

    # Sort: vehicles with pending maintenance first
    @vehicles = @vehicles.sort_by do |vehicle|
      has_pending = vehicle.maintenances.any? { |m| m.present? && m.status == "Pending" }
      has_pending ? 0 : 1
    end

    @maintenances = @vehicles.flat_map(&:maintenances).compact
  end

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
  # Analytics (placeholder if you already have this view)
  # ====================================================
  def analytics
    # If you already had an analytics implementation, paste it here.
    # Keeping this action prevents routing/before_action references from breaking.
  end

  # ====================================================
  # Export CSV
  # ====================================================
  def export_csv
    require "csv"

    from  = params[:from].present? ? Date.parse(params[:from]) : 30.days.ago.to_date
    to    = params[:to].present? ? Date.parse(params[:to]) : Date.today
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
        utilization  = total_days.positive? ? ((hours_sum / (total_days * 24.0)) * 100).round(1) : 0

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

  # ====================================================
  # Private methods
  # ====================================================
  private

  # Normalize so it matches the SQL regexp_replace normalization
  # e.g. "PCA-1234" == "PCA 1234" == "pca1234" -> "PCA1234"
  def normalize_plate(value)
    return "" if value.nil?

    value.to_s.upcase.gsub(/[^A-Za-z0-9]/, "")
  end

  def set_vehicle
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
      :agency_id,
      :primary_photo,
      :remove_primary_photo,
      :make_model_ui,
      :license_registration_ui,
      gallery_photos: []
    )
  end

  # Handles the "combined UI fields" you added for better data entry:
  # - make_model_ui => "Toyota Hilux" splits into make/model
  # - license_registration_ui => "PCA1234 / REG-0001" splits into plate + registration
  # Also auto-sets vehicle_type from VehicleCatalogEntry when available.
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

      # IMPORTANT: prevent validation crash if user typed only one word.
      # If no model provided, set a safe placeholder so the record can still save.
      if model_part.present?
        vehicle.model = model_part
      else
        vehicle.model = vehicle.model.presence || "Unknown"
      end
    end

    vehicle.make  = raw["make"].to_s.strip if vehicle.make.blank? && raw["make"].present?
    vehicle.model = raw["model"].to_s.strip if vehicle.model.blank? && raw["model"].present?

    # 3) If model is still blank, force safe placeholder to avoid "Model can't be blank"
    vehicle.model = "Unknown" if vehicle.model.blank? && vehicle.make.present?

    lr = raw["license_registration_ui"].to_s.strip
    if lr.present?
      normalized = lr.gsub(/\s+/, " ").strip
      chunks = normalized.split(%r{[/\-|,]}, 2).map(&:strip).reject(&:blank?)
      plate = chunks[0].to_s
      reg   = chunks.length > 1 ? chunks[1].to_s : ""

      vehicle.license_plate       = plate if plate.present?
      vehicle.registration_number = reg if reg.present?
    end

    # 5) Autofill vehicle_type from catalog only when blank
    if vehicle.vehicle_type.blank? && vehicle.make.present? && vehicle.model.present? && defined?(VehicleCatalogEntry)
      entry = VehicleCatalogEntry
              .where("LOWER(make) = ? AND LOWER(model) = ?", vehicle.make.downcase, vehicle.model.downcase)
              .first
      vehicle.vehicle_type = entry.vehicle_type if entry&.vehicle_type.present?
    end

    vehicle.vehicle_type = "Other" if vehicle.vehicle_type.blank?
  end

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

  def vehicle_types_for_select
    types = []
    if defined?(VehicleCatalogEntry)
      types = VehicleCatalogEntry.distinct.order(:vehicle_type).pluck(:vehicle_type).compact
    end
    fallback = ["Patrol Vehicle", "Bus", "Mini Bus", "SUV", "Pickup", "Van", "Truck", "Motorcycle", "Other"]
    (types + fallback).map(&:to_s).map(&:strip).reject(&:blank?).uniq
  end

  # ====================================================
  # Agency scoping
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

  def authorize_view!
    permission = PermissionService.new(current_user, @vehicle)
    return if permission.can?(:view_vehicle)

    redirect_to vehicles_path, alert: "You are not authorized to view this vehicle."
  end

  def authorize_edit!
    permission = PermissionService.new(current_user, @vehicle)
    return if permission.can?(:edit_vehicle)

    redirect_to vehicles_path, alert: "You are not authorized to edit this vehicle."
  end

  def authorize_create!
    return if current_user.fleet_manager? || current_user.admin? || current_user.manager?

    redirect_to vehicles_path, alert: "You are not authorized to add new vehicles."
  end

  def authorize_destroy!
    permission = PermissionService.new(current_user, @vehicle)
    return if permission.can?(:delete_vehicle)

    redirect_to vehicles_path, alert: "You are not authorized to delete this vehicle."
  end

  def authorize_report_issue!
    return if current_user.driver? ||
              current_user.maintenance_supervisor? ||
              current_user.fleet_manager? ||
              current_user.admin?

    redirect_to vehicles_path, alert: "You are not authorized to report issues."
  end

  def authorize_analytics!
    return if current_user.can_see_financial_data? || current_user.fleet_manager? || current_user.manager?

    redirect_to vehicles_path, alert: "You are not authorized to view analytics."
  end

  def authorize_maintenance!
    return if current_user.can_see_maintenance_data? || current_user.fleet_manager? || current_user.admin?

    redirect_to vehicles_path, alert: "You are not authorized to view maintenance data."
  end

  # ====================================================
  # Role helper
  # ====================================================
  def is_vmcott?
    current_user&.agency&.code.to_s.downcase == "vmcott"
  end
end
