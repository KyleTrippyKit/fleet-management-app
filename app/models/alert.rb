# frozen_string_literal: true

class Alert < ApplicationRecord
  # ============================================================
  # Associations
  # ============================================================
  belongs_to :vehicle, optional: true
  belongs_to :driver, optional: true
  belongs_to :agency, optional: true

  # ============================================================
  # Enums (STRING enums)
  # ============================================================
  enum :alert_type, {
    maintenance: "maintenance",
    safety: "safety",
    operational: "operational",
    financial: "financial",
    system: "system",
    critical_incident: "critical_incident"
  }, prefix: true

  enum :severity, {
    info: "info",
    warning: "warning",
    high_severity: "high_severity",
    critical: "critical"
  }, prefix: true

  # ✅ Updated statuses to align with your workflow
  # - active: created and waiting action
  # - acknowledged: maintenance/admin has accepted it
  # - awaiting_procurement: maintenance wants finance to do RFQ
  # - resolved: maintenance closed out the issue
  # - closed: optional archive state
  enum :status, {
    active: "active",
    acknowledged: "acknowledged",
    awaiting_procurement: "awaiting_procurement",
    resolved: "resolved",
    closed: "closed"
  }, prefix: true

  enum :priority, {
    low: "low",
    medium: "medium",
    high_priority: "high_priority",
    urgent: "urgent"
  }, prefix: true

  # ============================================================
  # Validations
  # ============================================================
  validates :title, presence: true
  validates :alert_type, presence: true
  validates :severity, presence: true
  validates :status, presence: true
  validates :priority, presence: true

  # Optional but recommended: lock alerts to agency for your workflow
  validate :agency_required_for_agency_workflow

  # ============================================================
  # Scopes
  # ============================================================
  scope :active_alerts, -> { where(status: "active") }
  scope :critical_alerts, -> { where(severity: "critical") }
  scope :urgent_alerts, -> { where(priority: "urgent") }
  scope :recent, -> { where("created_at >= ?", 24.hours.ago) }
  scope :unresolved, -> { where.not(status: %w[resolved closed]) }
  scope :for_vehicle, ->(vehicle) { where(vehicle_id: vehicle.id) }
  scope :for_agency,  ->(agency)  { where(agency_id: agency.id) }
  scope :needs_attention, -> { active_alerts.where("severity = 'critical' OR priority = 'urgent'") }

  # Compatibility helpers (if other code calls Alert.active / critical / urgent)
  def self.active = active_alerts
  def self.critical = critical_alerts
  def self.urgent = urgent_alerts

  def self.active_count = active_alerts.count
  def self.critical_count = critical_alerts.count
  def self.urgent_count = urgent_alerts.count
  def self.needs_attention_count = needs_attention.count

  # ============================================================
  # Class factories
  # ============================================================
  def self.create_critical_incident(params)
    create!(
      params.merge(
        alert_type: "critical_incident",
        severity: "critical",
        priority: "urgent",
        status: "active"
      )
    )
  end

  def self.create_maintenance_alert(vehicle, description, priority = "high_priority")
    create!(
      title: "Maintenance Alert: #{vehicle.license_plate}",
      description: description,
      alert_type: "maintenance",
      severity: (priority == "urgent" ? "critical" : "high_severity"),
      priority: priority,
      status: "active",
      vehicle_id: vehicle.id,
      driver_id: vehicle.driver_id,
      agency_id: vehicle.agency_id,
      location: vehicle.respond_to?(:current_location) ? (vehicle.current_location.presence || "Vehicle Location") : "Vehicle Location",
      created_by: "System"
    )
  end

  def self.create_safety_alert(vehicle, description, severity = "warning")
    create!(
      title: "Safety Alert: #{vehicle.license_plate}",
      description: description,
      alert_type: "safety",
      severity: severity,
      priority: (severity == "critical" ? "urgent" : "medium"),
      status: "active",
      vehicle_id: vehicle.id,
      location: vehicle.respond_to?(:current_location) ? (vehicle.current_location.presence || "Vehicle Location") : "Vehicle Location",
      created_by: "System",
      agency_id: vehicle.agency_id
    )
  end

  # ============================================================
  # Workflow booleans
  # ============================================================
  def needs_attention?
    status_active? && (severity_critical? || priority_urgent?)
  end

  def can_acknowledge?
    status_active?
  end

  def can_escalate?
    status_active? && !severity_critical?
  end

  def can_send_to_finance?
    # Maintenance/Admin chooses to send procurement to finance
    status_active? || status_acknowledged?
  end

  def can_resolve?
    status_active? || status_acknowledged? || status_awaiting_procurement?
  end

  # ============================================================
  # Workflow actions (safe, audit-friendly)
  # ============================================================
  def acknowledge!(user)
    # columns expected (optional):
    # acknowledged_at, acknowledged_by
    attrs = { status: "acknowledged" }
    attrs[:acknowledged_at] = Time.current if respond_to?(:acknowledged_at=)
    attrs[:acknowledged_by] = user&.name if respond_to?(:acknowledged_by=)
    attrs[:assigned_to] = user&.name if respond_to?(:assigned_to=)

    append_note!("Acknowledged by #{user&.name || 'Unknown'} at #{Time.current}") if respond_to?(:notes)
    update!(attrs)
  end

  def send_to_finance!(user)
    attrs = { status: "awaiting_procurement" }
    append_note!("Sent to Finance by #{user&.name || 'Unknown'} at #{Time.current}") if respond_to?(:notes)
    update!(attrs)
  end

  def resolve!(resolution_notes, user: nil)
    attrs = { status: "resolved" }
    attrs[:resolved_at] = Time.current if respond_to?(:resolved_at=)
    attrs[:resolved_by] = user&.name if respond_to?(:resolved_by=)
    attrs[:resolution_notes] = resolution_notes.to_s.strip if respond_to?(:resolution_notes=)

    append_note!("Resolved by #{user&.name || 'Unknown'} at #{Time.current}: #{resolution_notes}".strip) if respond_to?(:notes)
    update!(attrs)
  end

  def escalate!(user = nil)
    attrs = {
      priority: "urgent",
      severity: "critical"
    }
    append_note!("Escalated by #{user&.name || 'Unknown'} at #{Time.current}") if respond_to?(:notes)
    update!(attrs)
  end

  # ============================================================
  # Display helpers
  # ============================================================
  def display_priority
    case priority
    when "urgent"        then "🔴 URGENT"
    when "high_priority" then "🟠 HIGH"
    when "medium"        then "🟡 MEDIUM"
    when "low"           then "🟢 LOW"
    else priority.to_s.humanize
    end
  end

  def display_severity
    case severity
    when "critical"      then "🚨 CRITICAL"
    when "high_severity" then "⚠️ HIGH"
    when "warning"       then "⚠️ WARNING"
    when "info"          then "ℹ️ INFO"
    else severity.to_s.humanize
    end
  end

  def short_display
    if severity_critical? && priority_urgent?
      "🚨🔴"
    elsif severity_critical?
      "🚨"
    elsif priority_urgent?
      "🔴"
    elsif severity_high_severity? || priority_high_priority?
      "⚠️"
    else
      "ℹ️"
    end
  end

  def duration
    return nil unless respond_to?(:incident_time) && incident_time.present?
    ((Time.current - incident_time) / 3600.0).round(2)
  end

  def overdue?
    return false unless respond_to?(:estimated_resolution_time) && estimated_resolution_time.present?
    (status_active? || status_acknowledged?) && estimated_resolution_time < Time.current
  end

  # Backward compatibility helpers used elsewhere
  def high_severity? = severity_high_severity?
  def high_priority? = priority_high_priority?

  def humanized_alert_type = alert_type.to_s.humanize
  def humanized_severity = severity.to_s.tr("_", " ").humanize
  def humanized_priority = priority.to_s.tr("_", " ").humanize
  def humanized_status = status.to_s.humanize

  def to_display_string
    "#{display_severity} #{display_priority} - #{title}"
  end

  def vehicle_display_name
    vehicle&.display_name || vehicle&.license_plate || "No vehicle assigned"
  end

  def display_location
    location.presence || (vehicle.respond_to?(:current_location) ? vehicle.current_location : nil) || "Location not specified"
  end

  def summary_info
    {
      id: id,
      title: title,
      severity: severity,
      priority: priority,
      status: status,
      display_severity: display_severity,
      display_priority: display_priority,
      short_display: short_display,
      created_at: created_at,
      needs_attention: needs_attention?,
      overdue: overdue?,
      duration_hours: duration
    }
  end

  def priority_color
    case priority
    when "urgent"        then "danger"
    when "high_priority" then "warning"
    when "medium"        then "info"
    when "low"           then "success"
    else "secondary"
    end
  end

  def severity_color
    case severity
    when "critical"      then "danger"
    when "high_severity" then "warning"
    when "warning"       then "info"
    when "info"          then "primary"
    else "secondary"
    end
  end

  def dashboard_display
    {
      id: id,
      title: title,
      severity: severity,
      priority: priority,
      status: status,
      short_display: short_display,
      vehicle_name: vehicle_display_name,
      location: display_location,
      created_at: created_at,
      needs_attention: needs_attention?,
      can_acknowledge: can_acknowledge?,
      can_resolve: can_resolve?,
      can_send_to_finance: can_send_to_finance?
    }
  end

  private

  def agency_required_for_agency_workflow
    # If you REALLY allow system alerts without agency, remove this.
    return if agency_id.present? || vehicle&.agency_id.present?

    errors.add(:agency, "must be present (alerts belong to an agency)")
  end

  def append_note!(line)
    return unless respond_to?(:notes)
    self.notes = [notes.to_s.strip, line.to_s.strip].reject(&:blank?).join("\n")
  end
end
