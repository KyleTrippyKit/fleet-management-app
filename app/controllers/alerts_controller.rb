# frozen_string_literal: true

class AlertsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_alerts_module!
  before_action :ensure_not_vmcott!

  before_action :set_alert, only: [
    :show, :edit, :update, :destroy,
    :acknowledge, :resolve, :resolve_form,
    :escalate, :create_rfq
  ]

  before_action :authorize_create!,       only: [:new, :create]
  before_action :authorize_acknowledge!,  only: [:acknowledge]
  before_action :authorize_manage!,       only: [:resolve, :resolve_form, :escalate]
  before_action :authorize_finance!,      only: [:create_rfq]
  before_action :authorize_destroy!,      only: [:destroy]

  # ============================================================
  # INDEX
  # ============================================================
  def index
    @query      = params[:q].to_s.strip
    @status     = params[:status].presence
    @severity   = params[:severity].presence
    @priority   = params[:priority].presence
    @alert_type = params[:alert_type].presence

    scope = scoped_alerts

    if @query.present?
      q = "%#{@query}%"
      scope = scope.where(
        "alerts.title ILIKE ? OR alerts.description ILIKE ? OR alerts.location ILIKE ?",
        q, q, q
      )
    end

    scope = scope.where(status: @status)         if @status.present?
    scope = scope.where(severity: @severity)     if @severity.present?
    scope = scope.where(priority: @priority)     if @priority.present?
    scope = scope.where(alert_type: @alert_type) if @alert_type.present?

    @alerts = scope.order(created_at: :desc).page(params[:page]).per(20)
    @summary_stats = build_summary_stats
  end

  # ============================================================
  # SHOW
  # ============================================================
  def show
    related_scope = scoped_alerts.where.not(id: @alert.id)

    @related_alerts =
      if @alert.vehicle_id.present?
        related_scope.where(vehicle_id: @alert.vehicle_id).order(created_at: :desc).limit(10)
      elsif @alert.driver_id.present?
        related_scope.where(driver_id: @alert.driver_id).order(created_at: :desc).limit(10)
      else
        related_scope.order(created_at: :desc).limit(10)
      end
  end

  # ============================================================
  # NEW / CREATE
  # ============================================================
  def new
    @alert = Alert.new
    load_form_options
  end

  def create
    @alert = Alert.new(alert_params)

    # ✅ Always lock to creator's agency (primary rule)
    @alert.agency_id = current_user.agency_id

    # ✅ If user has no agency for some reason, try fallback from vehicle/driver
    if @alert.agency_id.blank?
      @alert.agency_id =
        (@alert.vehicle&.agency_id if @alert.respond_to?(:vehicle)) ||
        (@alert.driver&.agency_id  if @alert.respond_to?(:driver))
    end

    if @alert.agency_id.blank?
      load_form_options
      @alert.errors.add(:agency_id, "could not be determined")
      render :new, status: :unprocessable_entity
      return
    end

    # Default status
    @alert.status = "open" if @alert.status.blank?

    # Creator tracking (string column)
    if @alert.respond_to?(:created_by=)
      @alert.created_by = current_user.try(:name).presence || current_user.email
    end

    # Auto-fill driver if vehicle selected (optional convenience)
    if @alert.vehicle.present? && @alert.respond_to?(:driver_id=)
      @alert.driver_id ||= @alert.vehicle.driver_id
    end

    if @alert.save
      redirect_to alert_path(@alert), notice: "Alert created successfully."
    else
      load_form_options
      render :new, status: :unprocessable_entity
    end
  end

  # ============================================================
  # EDIT / UPDATE
  # ============================================================
  def edit
    load_form_options
  end

  def update
    # ✅ Never allow agency reassignment from params
    safe_params = alert_params.except(:agency_id)

    if @alert.update(safe_params)
      redirect_to alert_path(@alert), notice: "Alert updated successfully."
    else
      load_form_options
      render :edit, status: :unprocessable_entity
    end
  end

  # ============================================================
  # DESTROY (ADMIN ONLY)
  # ============================================================
  def destroy
    @alert.destroy
    redirect_to alerts_path, notice: "Alert deleted."
  end

  # ============================================================
  # ACKNOWLEDGE (ONLY FLEET MANAGER / ADMIN)
  # ============================================================
  def acknowledge
    if @alert.status.to_s == "resolved"
      redirect_back fallback_location: alert_path(@alert),
                    alert: "Resolved alerts cannot be acknowledged."
      return
    end

    # Track acknowledgment inside notes (since you don't have acknowledged_at/by columns)
    stamp = "#{Time.current.in_time_zone('America/Port_of_Spain').strftime('%Y-%m-%d %H:%M:%S %z')}"
    who   = current_user.try(:name).presence || current_user.email

    new_notes = []
    new_notes << @alert.notes.to_s.strip if @alert.notes.present?
    new_notes << "Acknowledged by #{who} at #{stamp}"
    new_notes = new_notes.reject(&:blank?).join("\n")

    @alert.update(status: "acknowledged", notes: new_notes)

    redirect_back fallback_location: alert_path(@alert), notice: "Alert acknowledged."
  end

  # ============================================================
  # RESOLVE FORM
  # ============================================================
  def resolve_form
  end

  # ============================================================
  # RESOLVE
  # ============================================================
  def resolve
    notes = params[:resolution_notes].to_s.strip

    stamp = "#{Time.current.in_time_zone('America/Port_of_Spain').strftime('%Y-%m-%d %H:%M:%S %z')}"
    who   = current_user.try(:name).presence || current_user.email

    new_notes = []
    new_notes << @alert.notes.to_s.strip if @alert.notes.present?
    new_notes << "Resolved by #{who} at #{stamp}" if @alert.status.to_s != "resolved"
    new_notes << "Resolution Notes: #{notes}" if notes.present?
    new_notes = new_notes.reject(&:blank?).join("\n")

    @alert.update(status: "resolved", notes: new_notes)
    redirect_to alert_path(@alert), notice: "Alert resolved."
  end

  # ============================================================
  # ESCALATE TO FINANCE
  # ============================================================
  def escalate
    stamp = "#{Time.current.in_time_zone('America/Port_of_Spain').strftime('%Y-%m-%d %H:%M:%S %z')}"
    who   = current_user.try(:name).presence || current_user.email

    new_notes = []
    new_notes << @alert.notes.to_s.strip if @alert.notes.present?
    new_notes << "Sent to Finance by #{who} at #{stamp}"
    new_notes = new_notes.reject(&:blank?).join("\n")

    @alert.update(status: "awaiting_procurement", notes: new_notes)
    redirect_back fallback_location: alert_path(@alert), notice: "Alert sent to Finance."
  end

  # ============================================================
  # CREATE RFQ FROM ALERT (FINANCE/ADMIN)
  # ============================================================
  def create_rfq
    vehicle_label =
      if @alert.vehicle.present?
        "#{@alert.vehicle.license_plate} - #{@alert.vehicle.make} #{@alert.vehicle.model}"
      else
        "Vehicle"
      end

    redirect_to new_rfq_path(
      from_alert_id: @alert.id,
      vehicle_id: @alert.vehicle_id,
      driver_id: @alert.driver_id,
      subject: "RFQ for #{vehicle_label}",
      description: @alert.description.to_s
    )
  end

  # ============================================================
  # PRIVATE
  # ============================================================
  private

  def set_alert
    @alert = scoped_alerts.find(params[:id])
  end

  # ✅ STRICT: Only agency that created the alert can see it
  def scoped_alerts
    base = Alert.includes(:vehicle, :driver, :agency)
    return base if current_user.admin?

    return base.none if current_user.agency_id.blank?
    base.where(agency_id: current_user.agency_id)
  end

  def authorize_alerts_module!
    return if current_user.admin?
    return if current_user.driver? ||
              current_user.fleet_manager? ||
              current_user.supervisor? ||
              current_user.maintenance_supervisor? ||
              current_user.finance?

    redirect_to dashboard_path, alert: "Not authorized to access alerts."
  end

  def ensure_not_vmcott!
    if current_user.agency&.code.to_s.upcase == "VMCOTT"
      redirect_to dashboard_path, alert: "Alerts are managed by agencies only (not VMCOTT)."
    end
  end

  def authorize_create!
    return if current_user.admin?
    return if current_user.driver? ||
              current_user.fleet_manager? ||
              current_user.supervisor? ||
              current_user.maintenance_supervisor?

    redirect_to alerts_path, alert: "You are not allowed to create alerts."
  end

  # ✅ Only Fleet Manager (or Admin) can acknowledge
  def authorize_acknowledge!
    return if current_user.admin? || current_user.fleet_manager?
    redirect_back fallback_location: alerts_path, alert: "Only Fleet Managers can acknowledge alerts."
  end

  # ✅ Resolve / escalate allowed for management roles
  def authorize_manage!
    return if current_user.admin?
    return if current_user.fleet_manager? ||
              current_user.supervisor? ||
              current_user.maintenance_supervisor?

    redirect_back fallback_location: alerts_path, alert: "You are not allowed to manage alerts."
  end

  def authorize_finance!
    return if current_user.admin? || current_user.finance?
    redirect_back fallback_location: alerts_path, alert: "Finance only."
  end

  def authorize_destroy!
    return if current_user.admin?
    redirect_back fallback_location: alerts_path, alert: "Only admins can delete alerts."
  end

  def build_summary_stats
    base = scoped_alerts
    {
      total: base.count,
      open: base.where(status: "open").count,
      acknowledged: base.where(status: "acknowledged").count,
      awaiting_procurement: base.where(status: "awaiting_procurement").count,
      resolved: base.where(status: "resolved").count,
      critical: base.where(severity: "critical").count
    }.with_indifferent_access
  end

  def load_form_options
    @alert_types = Alert.alert_types.keys
    @severities  = Alert.severities.keys
    @priorities  = Alert.priorities.keys
    @statuses    = Alert.statuses.keys
  end

  def alert_params
    params.require(:alert).permit(
      :title,
      :alert_type,
      :description,
      :severity,
      :priority,
      :status,
      :vehicle_id,
      :driver_id,
      :location,
      :incident_time
    )
  end
end
