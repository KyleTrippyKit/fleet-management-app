# app/models/alert.rb
class Alert < ApplicationRecord
  belongs_to :vehicle, optional: true
  belongs_to :driver, optional: true
  belongs_to :agency, optional: true
  
  # Alert types
  enum :alert_type, {
    maintenance: 'maintenance',
    safety: 'safety',
    operational: 'operational',
    financial: 'financial',
    system: 'system',
    critical_incident: 'critical_incident'
  }
  
  # Severity levels
  enum :severity, {
    info: 'info',
    warning: 'warning',
    high_severity: 'high_severity',
    critical: 'critical'
  }
  
  # Status
  enum :status, {
    active: 'active',
    acknowledged: 'acknowledged',
    in_progress: 'in_progress',
    resolved: 'resolved',
    closed: 'closed'
  }
  
  # Priority
  enum :priority, {
    low: 'low',
    medium: 'medium',
    high_priority: 'high_priority',
    urgent: 'urgent'
  }
  
  # Validations
  validates :title, presence: true
  validates :alert_type, presence: true
  validates :severity, presence: true
  validates :status, presence: true
  validates :priority, presence: true
  
  # Scopes
  scope :active_alerts, -> { where(status: 'active') }
  scope :critical_alerts, -> { where(severity: 'critical') }
  scope :urgent_alerts, -> { where(priority: 'urgent') }
  scope :recent, -> { where('created_at >= ?', 24.hours.ago) }
  scope :unresolved, -> { where.not(status: ['resolved', 'closed']) }
  scope :for_vehicle, ->(vehicle) { where(vehicle_id: vehicle.id) }
  scope :for_agency, ->(agency) { where(agency_id: agency.id) }
  scope :needs_attention, -> { active_alerts.where("severity = 'critical' OR priority = 'urgent'") }
  
  # Class methods for accessing scopes
  def self.active
    active_alerts
  end
  
  def self.critical
    critical_alerts
  end
  
  def self.urgent
    urgent_alerts
  end
  
  # Convenience class methods for counts
  def self.active_count
    active_alerts.count
  end
  
  def self.critical_count
    critical_alerts.count
  end
  
  def self.urgent_count
    urgent_alerts.count
  end
  
  def self.needs_attention_count
    needs_attention.count
  end
  
  # Class methods for creating alerts
  def self.create_critical_incident(params)
    create!(
      params.merge(
        alert_type: 'critical_incident',
        severity: 'critical',
        priority: 'urgent',
        status: 'active'
      )
    )
  end
  
  def self.create_maintenance_alert(vehicle, description, priority = 'high_priority')
    create!(
      title: "Maintenance Alert: #{vehicle.license_plate}",
      description: description,
      alert_type: 'maintenance',
      severity: priority == 'urgent' ? 'critical' : 'high_severity',
      priority: priority,
      status: 'active',
      vehicle_id: vehicle.id,
      driver_id: vehicle.driver_id,
      agency_id: vehicle.agency_id,
      location: vehicle.current_location.presence || "Vehicle Location",
      created_by: 'System'
    )
  end
  
  # Create a safety alert
  def self.create_safety_alert(vehicle, description, severity = 'warning')
    create!(
      title: "Safety Alert: #{vehicle.license_plate}",
      description: description,
      alert_type: 'safety',
      severity: severity,
      priority: severity == 'critical' ? 'urgent' : 'medium',
      status: 'active',
      vehicle_id: vehicle.id,
      location: vehicle.current_location.presence || "Vehicle Location",
      created_by: 'System'
    )
  end
  
  # Instance methods
  
  def needs_attention?
    active? && (critical? || urgent?)
  end
  
  def acknowledge!(user)
    update!(
      status: 'acknowledged',
      assigned_to: user.name,
      notes: "#{notes}\nAcknowledged by #{user.name} at #{Time.now}".strip
    )
  end
  
  def resolve!(resolution_notes)
    update!(
      status: 'resolved',
      notes: "#{notes}\nResolved: #{resolution_notes}".strip,
      estimated_resolution_time: Time.now
    )
  end
  
  def escalate!
    update!(
      priority: 'urgent',
      severity: 'critical',
      notes: "#{notes}\nEscalated to critical at #{Time.now}".strip
    )
  end
  
  def display_priority
    case priority
    when 'urgent' then '🔴 URGENT'
    when 'high_priority' then '🟠 HIGH'
    when 'medium' then '🟡 MEDIUM'
    when 'low' then '🟢 LOW'
    else priority.humanize
    end
  end
  
  def display_severity
    case severity
    when 'critical' then '🚨 CRITICAL'
    when 'high_severity' then '⚠️ HIGH'
    when 'warning' then '⚠️ WARNING'
    when 'info' then 'ℹ️ INFO'
    else severity.humanize
    end
  end
  
  def short_display
    case
    when critical? && urgent?
      '🚨🔴'
    when critical?
      '🚨'
    when urgent?
      '🔴'
    when high_severity? || high_priority?
      '⚠️'
    else
      'ℹ️'
    end
  end
  
  def duration
    return nil unless incident_time
    (Time.now - incident_time).to_i / 3600.0 # hours
  end
  
  def overdue?
    return false unless estimated_resolution_time
    status.in?(%w[active acknowledged]) && estimated_resolution_time < Time.now
  end
  
  # Helper methods for backward compatibility
  def high_severity?
    severity == 'high_severity'
  end
  
  def high_priority?
    priority == 'high_priority'
  end
  
  # For forms and displays
  def humanized_alert_type
    alert_type.to_s.humanize
  end
  
  def humanized_severity
    severity.to_s.gsub('_', ' ').humanize
  end
  
  def humanized_priority
    priority.to_s.gsub('_', ' ').humanize
  end
  
  def humanized_status
    status.to_s.humanize
  end
  
  # For your view templates
  def to_display_string
    "#{display_severity} #{display_priority} - #{title}"
  end
  
  def vehicle_display_name
    vehicle&.display_name || 'No vehicle assigned'
  end
  
  def display_location
    location.presence || vehicle&.current_location || 'Location not specified'
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
      duration: duration&.round(1)
    }
  end
  
  # Color coding for UI
  def priority_color
    case priority
    when 'urgent' then 'red'
    when 'high_priority' then 'orange'
    when 'medium' then 'yellow'
    when 'low' then 'green'
    else 'gray'
    end
  end
  
  def severity_color
    case severity
    when 'critical' then 'red'
    when 'high_severity' then 'orange'
    when 'warning' then 'yellow'
    when 'info' then 'blue'
    else 'gray'
    end
  end
  
  # Quick actions
  def can_acknowledge?
    active?
  end
  
  def can_resolve?
    active? || acknowledged? || in_progress?
  end
  
  def can_escalate?
    active? && !critical?
  end
  
  # For dashboard display - simplified version
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
      can_resolve: can_resolve?
    }
  end
end