# frozen_string_literal: true

class MaintenancesController < ApplicationController
  before_action :authenticate_user!

  # ✅ ONLY VMCOTT admin OR VMCOTT maintenance role can write.
  # 🚫 PTSC admin (and any other agency admin) is READ-ONLY.
  before_action :enforce_vmcott_write_access!, only: [
    :new, :create, :edit, :update, :destroy, :mark_completed, :update_gantt, :confirm_delete
  ]

  # Vehicle is used for nested routes, show/edit/update/destroy redirects, etc.
  # We do NOT run this for gantt/update_gantt because those are global endpoints.
  # We also skip for new/create because those can be standalone (no vehicle chosen yet).
  before_action :set_vehicle, except: [:gantt, :update_gantt, :new, :create]

  before_action :set_maintenance, only: [
    :show, :edit, :update, :destroy, :mark_completed, :confirm_delete, :update_gantt
  ]

  # ------------------------------------------------------------
  # GET /gantt
  # ------------------------------------------------------------
  def gantt
    Rails.logger.debug("=== GANTT CHART ===") if Rails.env.development?

    base = Maintenance.includes(:vehicle)
                      .where.not(start_date: nil)
                      .where.not(end_date: nil)
                      .order(:start_date)

    # ✅ Agencies see ONLY their vehicles/maintenances
    base = scope_for_current_user(base)

    # ✅ NEW: if user clicked "View Timeline" from Maintenance show page,
    # auto-filter to that vehicle instantly.
    if params[:vehicle_id].present?
      base = base.where(vehicle_id: params[:vehicle_id])
    elsif params[:vehicle_search].present?
      term = params[:vehicle_search].to_s.downcase.strip
      base = base.joins(:vehicle).where(
        "LOWER(vehicles.registration_number) LIKE :q OR LOWER(vehicles.license_plate) LIKE :q OR LOWER(vehicles.make) LIKE :q OR LOWER(vehicles.model) LIKE :q",
        q: "%#{term}%"
      )
    end

    Rails.logger.debug("Maintenances w/ dates (scoped): #{base.count}") if Rails.env.development?

    @maintenances = apply_filters(base)
    Rails.logger.debug("After filters: #{@maintenances.count}") if Rails.env.development?

    prepare_gantt_data(@maintenances)

    # ✅ Filter dropdowns must also be scoped
    @service_owners      = VehicleScope.for_user(current_user).distinct.pluck(:service_owner).compact.sort
    @vehicles_for_filter = VehicleScope.for_user(current_user).order(:make, :model)

    # ✅ Stats must be scoped (use base after scoping + vehicle focus)
    @overdue_count  = overdue_relation(base).count
    @total_cost     = @maintenances.sum(:cost).to_f
    @vehicles_count = VehicleScope.for_user(current_user).count

    render :gantt
  end

  # ------------------------------------------------------------
  # PATCH /maintenances/:id/update_gantt
  # ------------------------------------------------------------
  def update_gantt
    unless params[:maintenance].present?
      return render json: { success: false, errors: ["No data provided"] }, status: :bad_request
    end

    if @maintenance.update(maintenance_params)
      render json: {
        success: true,
        message: "Maintenance updated successfully",
        maintenance: (@maintenance.respond_to?(:gantt_task_data) ? @maintenance.gantt_task_data : @maintenance.as_json)
      }
    else
      render json: { success: false, errors: @maintenance.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # ------------------------------------------------------------
  # GET /vehicles/:vehicle_id/maintenances
  # ------------------------------------------------------------
  def index
    base =
      if @vehicle.present?
        # ✅ forbid agencies from opening another agency's vehicle
        return head(:forbidden) unless VehicleScope.for_user(current_user).where(id: @vehicle.id).exists?

        @vehicle.maintenances
      else
        Maintenance.includes(:vehicle)
      end

    base = scope_for_current_user(base)

    # ✅ FIX: qualify columns to avoid "status is ambiguous"
    @maintenances = base.order(
      Arel.sql("
        CASE maintenances.status
          WHEN 'Pending' THEN 0
          WHEN 'In Progress' THEN 1
          WHEN 'Completed' THEN 2
          ELSE 3
        END ASC,
        COALESCE(maintenances.start_date, maintenances.date) ASC
      ")
    )
  end

  # ------------------------------------------------------------
  # GET /maintenances/:id
  # ------------------------------------------------------------
  def show; end

  # ------------------------------------------------------------
  # GET /maintenances/:id/confirm_delete
  # ------------------------------------------------------------
  def confirm_delete; end

  # ------------------------------------------------------------
  # DELETE /maintenances/:id
  # ------------------------------------------------------------
  def destroy
    @maintenance.destroy

    if @vehicle.present?
      redirect_to vehicle_path(@vehicle), notice: "Maintenance record was successfully deleted."
    else
      redirect_to maintenance_dashboard_vehicles_path, notice: "Maintenance record was successfully deleted."
    end
  end

  # ------------------------------------------------------------
  # PATCH /maintenances/:id/mark_completed
  # ------------------------------------------------------------
  def mark_completed
    if @maintenance.update(status: "Completed")
      redirect_to maintenance_dashboard_vehicles_path, notice: "Maintenance marked as completed."
    else
      redirect_to maintenance_dashboard_vehicles_path, alert: "Could not mark maintenance as completed."
    end
  end

  # ------------------------------------------------------------
  # GET /maintenances/new
  # ------------------------------------------------------------
  def new
    @service_providers = ServiceProvider.all

    if params[:vehicle_id].present?
      @vehicle = VehicleScope.for_user(current_user).find(params[:vehicle_id])
      @maintenance = @vehicle.maintenances.new
    else
      @maintenance = Maintenance.new
    end

    # Defaults
    @maintenance.mileage ||= @vehicle&.mileage
    @maintenance.start_date ||= Date.current
    @maintenance.end_date ||= Date.current + 7.days

    if params[:source] == "driver_report"
      @maintenance.source = "Driver Report"
      @maintenance.urgency = "high"
      @maintenance.service_type ||= "Repair"
      @maintenance.notes ||= "Issue reported by driver"
      @maintenance.status ||= "Pending"
      flash.now[:info] = "Please describe the issue in detail below. Your report will be reviewed by maintenance staff."
    end

    @from_report_issue = (params[:source] == "driver_report")
  end

  # ------------------------------------------------------------
  # POST /maintenances
  # ------------------------------------------------------------
  def create
    @service_providers = ServiceProvider.all

    @vehicle =
      if params[:vehicle_id].present?
        VehicleScope.for_user(current_user).find(params[:vehicle_id])
      elsif params.dig(:maintenance, :vehicle_id).present?
        VehicleScope.for_user(current_user).find(params.dig(:maintenance, :vehicle_id))
      end

    @maintenance =
      if @vehicle
        @vehicle.maintenances.new(maintenance_params)
      else
        Maintenance.new(maintenance_params)
      end

    validate_date_order(@maintenance)

    if @maintenance.errors.empty? && @maintenance.save
      # ✅ Update vehicle mileage if current mileage is provided
      if params[:maintenance][:mileage].present? && @vehicle.present?
        @vehicle.update(mileage: params[:maintenance][:mileage])
      end

      # ✅ Handle next_maintenance_mileage virtual attribute
      if params[:maintenance][:next_maintenance_mileage].present? && @vehicle.present?
        # Store this in a session or use it for notifications
        session[:next_maintenance_mileage] = params[:maintenance][:next_maintenance_mileage]
      end

      # ✅ part_in_stock may not exist in some schemas → safely handle
      part_in_stock_value =
        if @maintenance.respond_to?(:part_in_stock)
          @maintenance.part_in_stock
        elsif @maintenance.respond_to?(:part_in_stock?)
          @maintenance.part_in_stock?
        else
          nil
        end

      MaintenanceMailer.notify_store(@maintenance).deliver_later if part_in_stock_value == false

      if @vehicle
        redirect_to vehicle_path(@vehicle), notice: "Maintenance record was successfully created."
      else
        redirect_to gantt_path, notice: "Maintenance record was successfully created."
      end
    else
      flash.now[:alert] = "Please correct the errors below."
      render :new, status: :unprocessable_entity
    end
  end

  # ------------------------------------------------------------
  # GET /maintenances/:id/edit
  # ------------------------------------------------------------
  def edit
    @service_providers = ServiceProvider.all
  end

  # ------------------------------------------------------------
  # PATCH/PUT /maintenances/:id
  # ------------------------------------------------------------
  def update
    @service_providers = ServiceProvider.all

    validate_date_order(@maintenance)

    if @maintenance.errors.empty? && @maintenance.update(maintenance_params)
      # ✅ Update vehicle mileage if current mileage is provided
      if params[:maintenance][:mileage].present? && @vehicle.present?
        @vehicle.update(mileage: params[:maintenance][:mileage])
      end

      if request.xhr?
        render json: { success: true, message: "Maintenance updated successfully" }
      else
        if @vehicle
          redirect_to vehicle_path(@vehicle), notice: "Maintenance record was successfully updated."
        else
          redirect_to maintenance_dashboard_vehicles_path, notice: "Maintenance record was successfully updated."
        end
      end
    else
      if request.xhr?
        render json: { success: false, errors: @maintenance.errors.full_messages }, status: :unprocessable_entity
      else
        flash.now[:alert] = "Please correct the errors below."
        render :edit, status: :unprocessable_entity
      end
    end
  end

  private

  # ---------------- SECURITY ----------------

  def enforce_vmcott_write_access!
    agency_code = current_user&.agency&.code.to_s.upcase

    vmcott_maintenance_role =
      (current_user.respond_to?(:fleet_manager?) && current_user.fleet_manager?) ||
      (current_user.respond_to?(:supervisor?) && current_user.supervisor?)

    allowed = (agency_code == "VMCOTT") && (current_user.admin? || vmcott_maintenance_role)
    return if allowed

    redirect_back(
      fallback_location: maintenance_dashboard_vehicles_path,
      alert: "Read-only: only VMCOTT maintenance staff can create/update maintenance."
    )
  end

  # ---------------- SCOPING ----------------

  def scope_for_current_user(relation)
    agency_code = current_user&.agency&.code.to_s.upcase
    return relation if agency_code == "VMCOTT"

    relation.joins(:vehicle).where(vehicles: { agency_id: current_user.agency_id })
  end

  def set_vehicle
    return unless params[:vehicle_id].present?
    @vehicle = VehicleScope.for_user(current_user).find_by(id: params[:vehicle_id])
  end

  def set_maintenance
    base = scope_for_current_user(Maintenance.includes(:vehicle))
    @maintenance = base.find(params[:id])
    @vehicle ||= @maintenance.vehicle
  end

  # ---------------- PARAMS / VALIDATION ----------------

  def maintenance_params
    params.require(:maintenance).permit(
      :date, :next_due_date, :reminder_sent_at, :service_type, :cost,
      :notes, :mileage, :status, :assignment_type,
      :service_provider_id, :estimated_delivery_date, :source, :start_date,
      :end_date, :category, :urgency, :vehicle_id,
      # Keep existing fields
      :part_in_stock,
      # New virtual attribute for next maintenance mileage
      :next_maintenance_mileage
    )
  end

  def validate_date_order(maintenance)
    return unless maintenance.start_date.present? && maintenance.end_date.present?
    maintenance.errors.add(:end_date, "must be after start date") if maintenance.end_date < maintenance.start_date
  end

  # ---------- FILTERS ----------

  def apply_filters(rel)
    filtered = rel

    if params[:status].present? && params[:status] != "All Statuses" && params[:status] != ""
      if params[:status] == "Overdue"
        filtered = overdue_relation(filtered)
      else
        filtered = filtered.where(status: params[:status])
      end
    end

    if params[:vehicle_id].present? && params[:vehicle_id] != ""
      filtered = filtered.where(vehicle_id: params[:vehicle_id])
    end

    if params[:vehicle_search].present?
      term = params[:vehicle_search].to_s.downcase.strip
      filtered = filtered.joins(:vehicle).where(
        "LOWER(vehicles.registration_number) LIKE :q OR LOWER(vehicles.license_plate) LIKE :q OR LOWER(vehicles.make) LIKE :q OR LOWER(vehicles.model) LIKE :q",
        q: "%#{term}%"
      )
    end

    if params[:owner].present? && params[:owner] != "All Owners" && params[:owner] != ""
      filtered = filtered.joins(:vehicle).where(vehicles: { service_owner: params[:owner] })
    end

    filter_by_date_range(filtered)
  end

  def overdue_relation(rel)
    rel.where("end_date < ?", Date.current)
       .where.not(status: "Completed")
  end

  def filter_by_date_range(rel)
    return rel unless params[:date_range].present?

    case params[:date_range]
    when "all_time" then rel
    when "last_7_days" then within_range(rel, Date.current - 7.days, Date.current)
    when "last_30_days" then within_range(rel, Date.current - 30.days, Date.current)
    when "last_3_months" then within_range(rel, Date.current - 3.months, Date.current)
    when "last_6_months" then within_range(rel, Date.current - 6.months, Date.current)
    when "last_year" then within_range(rel, Date.current - 1.year, Date.current)
    when "next_7_days" then within_range(rel, Date.current, Date.current + 7.days)
    when "next_30_days" then within_range(rel, Date.current, Date.current + 30.days)
    when "next_3_months" then within_range(rel, Date.current, Date.current + 3.months)
    when "next_6_months" then within_range(rel, Date.current, Date.current + 6.months)
    when "next_year" then within_range(rel, Date.current, Date.current + 1.year)
    when "custom"
      if params[:start_date].present? && params[:end_date].present?
        s = Date.parse(params[:start_date])
        e = Date.parse(params[:end_date])
        within_range(rel, s, e)
      else
        rel
      end
    when "7", "30", "90"
      days = params[:date_range].to_i
      within_range(rel, Date.current, Date.current + days.days)
    else
      rel
    end
  end

  def within_range(rel, start_date, end_date)
    rel.where("end_date >= ? AND start_date <= ?", start_date, end_date)
  end

  # ---------- GANTT DATA ----------

  def prepare_gantt_data(maintenances)
    @gantt_tasks = []
    @gantt_links = []
    return if maintenances.blank?

    grouped = maintenances.group_by(&:vehicle)

    grouped.each do |vehicle, rows|
      next unless vehicle.present? && rows.any?

      starts = rows.map(&:start_date).compact
      ends   = rows.map(&:end_date).compact
      next if starts.empty? || ends.empty?

      vehicle_start = starts.min
      vehicle_end   = ends.max

      @gantt_tasks << {
        id: "vehicle_#{vehicle.id}",
        text: "#{vehicle.make} #{vehicle.model} (#{vehicle.registration_number})",
        start_date: vehicle_start.strftime("%Y-%m-%d"),
        end_date: vehicle_end.strftime("%Y-%m-%d"),
        parent: "0",
        type: "vehicle",
        progress: 0,
        open: true,
        color: "#6c757d",
        status: "Active",
        urgency: "Normal",
        details: {
          service_owner: vehicle.service_owner,
          registration_number: vehicle.registration_number,
          current_driver: vehicle.driver&.name || "Unassigned",
          vehicle_type: vehicle.vehicle_type,
          current_mileage: vehicle.mileage
        }
      }

      rows.each do |m|
        next unless m.start_date && m.end_date

        status  = m.status.presence  || "Pending"
        urgency = m.urgency.presence || "Normal"

        color =
          if status == "Completed"
            "#198754"
          elsif m.end_date < Date.current && status != "Completed"
            "#dc3545"
          else
            "#ffc107"
          end

        progress = (status == "Completed") ? 1 : 0.5

        @gantt_tasks << {
          id: "maintenance_#{m.id}",
          text: m.service_type.to_s.presence || "Maintenance ##{m.id}",
          start_date: m.start_date.strftime("%Y-%m-%d"),
          end_date: m.end_date.strftime("%Y-%m-%d"),
          parent: "vehicle_#{vehicle.id}",
          type: "maintenance",
          progress: progress,
          open: true,
          color: color,
          status: status,
          urgency: urgency,
          overdue: (status != "Completed" && m.end_date < Date.current),
          details: {
            status: status,
            urgency: urgency,
            cost: m.cost.to_f || 0,
            notes: m.notes.to_s,
            vehicle_id: vehicle.id,
            maintenance_id: m.id,
            duration: (m.respond_to?(:duration_days) ? m.duration_days : nil),
            service_owner: vehicle.service_owner,
            service_type: m.service_type,
            category: m.category,
            mileage: m.mileage
          }
        }
      end
    end

    @gantt_json = { data: @gantt_tasks, links: @gantt_links }.to_json
  end
end