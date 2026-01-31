class Vehicle < ApplicationRecord
  has_many :alerts, dependent: :destroy
  # ------------------------------------------------------------
  # Virtual attributes for form handling
  # ------------------------------------------------------------
  attr_accessor :remove_primary_photo
  # Virtual attributes for form UI helpers (not DB columns)
  attr_accessor :make_model_ui, :license_registration_ui

  
  # ------------------------------------------------------------
  # Associations
  # ------------------------------------------------------------
  belongs_to :agency
  belongs_to :driver, optional: true   # One driver per vehicle

  has_many :maintenances, dependent: :destroy
  has_many :trips, dependent: :destroy
  has_many :vehicle_documents, dependent: :destroy

  # ✅ ActiveStorage attachments for real photo uploads
  has_one_attached :primary_photo  # Main vehicle photo
  has_many_attached :gallery_photos  # Additional photos

  # ------------------------------------------------------------
  # Trinidad & Tobago license plate rules
  # ------------------------------------------------------------
  TT_PRIMARY_PREFIXES  = %w[P H T G].freeze
  TT_SPECIAL_PREFIXES  = %w[CD RR D R].freeze

  # ----------------------------
  # Normalization / cleanup
  # ----------------------------
  before_validation :normalize_license_plate
  before_validation :sync_registration_number_from_license_plate
  before_validation :normalize_vehicle_fields
  before_validation :sync_service_owner_from_agency

  # ------------------------------------------------------------
  # Validations
  # ------------------------------------------------------------
  validates :agency_id, presence: true
  validates :make, :model, :vehicle_type, :license_plate, presence: true
  validates :chassis_number, :serial_number, :year_of_manufacture, presence: true

  validates :license_plate, uniqueness: true
  validates :registration_number, uniqueness: true, allow_blank: true
  
  # Service owner validation - now derived from agency
  validate :service_owner_matches_agency
  
  validates :license_plate, format: {
    with: /\A([A-Z]{3}|CD|RR|D|R)-\d{1,4}\z/,
    message: "must follow Trinidad format (ABC-1234)"
  }

  # ------------------------------------------------------------
  # Custom Validation
  # ------------------------------------------------------------
  def service_owner_matches_agency
    if service_owner.present? && agency.present? && service_owner != agency.code
      errors.add(:service_owner, "must match agency code (#{agency.code})")
    end
  end

  # ------------------------------------------------------------
  # Service Owner Lock (derived from agency)
  # ------------------------------------------------------------

  # Always expose service_owner as the agency code (backward compatible reads)
  def service_owner
    agency&.code || self[:service_owner]
  end

  # NEVER lookup agency based on service_owner input
  # Just store the raw value (legacy) but do not trust it for logic
  def service_owner=(value)
    self[:service_owner] = value
  end
  
  # Get service owner display name
  def service_owner_display
    agency&.display_name || service_owner
  end

  def license_plate_with_details
    "#{license_plate} - #{make} #{model} (#{year_of_manufacture})"
  end

  # ------------------------------------------------------------
  # License plate normalization and sync
  # ------------------------------------------------------------
  def normalize_license_plate
    return if license_plate.blank?

    plate = license_plate.to_s.strip.upcase.gsub(/\s+/, "").gsub(/[^A-Z0-9]/, "")
    prefix  = plate[/\A[A-Z]+/]
    numbers = plate[/\d+/]
    return if prefix.blank? || numbers.blank?

    prefix = prefix[0,3] if prefix.length > 3
    self.license_plate = "#{prefix}-#{numbers}"
  end

  def sync_registration_number_from_license_plate
    # If user only enters plate, keep legacy field populated
    self.registration_number = license_plate if registration_number.blank? && license_plate.present?
  end

  # Wherever you display registration_number, always fall back safely:
  def registration_or_plate
    registration_number.presence || license_plate
  end

  # ----------------------------
  # Normalization helpers
  # ----------------------------
  def normalize_vehicle_fields
    # Trim spaces everywhere
    self.make = make.to_s.strip if make.present?
    self.model = model.to_s.strip if model.present?

    # Standardize plate formatting (common approach) - keep our TT format logic
    self.license_plate = license_plate.to_s.strip.upcase if license_plate.present?

    # Registration can be optional; if present, normalize it
    self.registration_number = registration_number.to_s.strip.upcase if registration_number.present?

    # Optional normalizations
    self.color = color.to_s.strip if color.present?
    self.vehicle_type = vehicle_type.to_s.strip if vehicle_type.present?

    # If you're now using body_style as drive type
    self.body_style = body_style.to_s.strip.upcase if body_style.present?

    self.fuel_type = fuel_type.to_s.strip if fuel_type.present?
    self.transmission = transmission.to_s.strip if transmission.present?
  end

  # This is the "lock" - sync service_owner from agency
  def sync_service_owner_from_agency
    return unless agency
    self[:service_owner] = agency.code.to_s.strip
  end

  # ------------------------------------------------------------
  # Scopes for filtering
  # ------------------------------------------------------------
  scope :by_service_owner, ->(owner) { 
    if owner.present?
      joins(:agency).where(agencies: { code: owner })
    end
  }
  
  scope :by_agency, ->(agency_id) { where(agency_id: agency_id) if agency_id.present? }
  
  scope :by_type, ->(type) { where(vehicle_type: type) if type.present? }
  scope :with_active_maintenance, -> { 
    joins(:maintenances).where(maintenances: { status: 'Pending' }).distinct 
  }
  
  # Active vehicles available for assignment
  scope :active, -> {
    # Temporary fix: return all vehicles for now
    # We'll fix the SQL issue separately
    all
    # Original problematic code:
    # left_joins(:maintenances)
    #   .where("maintenances.status IS NULL OR maintenances.status NOT IN (?)", ['Pending', 'In Progress'])
    #   .distinct
  }
  
  # Available for assignment (not assigned to any driver OR assigned to specific driver for editing)
  scope :available_for_assignment, ->(current_driver_id = nil) {
    if current_driver_id
      where("driver_id IS NULL OR driver_id = ?", current_driver_id)
    else
      where(driver_id: nil)
    end
  }

  # Agency-specific scopes
  scope :for_agency, ->(agency_code) {
    joins(:agency).where(agencies: { code: agency_code }) if agency_code.present?
  }
  
  scope :ptsc_vehicles, -> { for_agency('PTSC') }
  scope :ttps_vehicles, -> { for_agency('TTPS') }
  scope :ttdf_vehicles, -> { for_agency('TTDF') }
  scope :fire_vehicles, -> { for_agency('FIRE') }
  scope :health_vehicles, -> { for_agency('HEALTH') }
  scope :education_vehicles, -> { for_agency('EDUCATION') }

  # ------------------------------------------------------------
  # Image helpers (Asset Pipeline + ActiveStorage)
  # ------------------------------------------------------------
  def asset_image_path
    # Map makes to your placeholder images
    case make
    when 'Ford'
      'placeholders/Ford.webp'
    when 'Higer'
      'placeholders/Higer.jpg'
    when 'Isuzu'
      'placeholders/Isuzu.jpg'
    when 'Nissan'
      'placeholders/Nissan.webp'
    when 'Suzuki'
      'placeholders/Suzuki.jpg'
    when 'Toyota'
      model == 'Hilux' ? 'placeholders/Toyota.jpeg' : 'placeholders/toyota.jpg'
    else
      'placeholders/default.png'
    end
  end

  def primary_image_url
    ActionController::Base.helpers.asset_path(asset_image_path)
  end

  def display_image
    if primary_photo.attached?
      primary_photo
    else
      primary_image_url
    end
  end

  # ------------------------------------------------------------
  # Status methods
  # ------------------------------------------------------------
  def status
    if has_overdue_maintenance?
      'overdue'
    elsif has_active_maintenance?
      'maintenance'
    else
      'active'
    end
  end

  def fuel_level
    self[:fuel_level] || 0
  end
  
  def status_badge_class
    case status
    when 'active' then 'bg-success'
    when 'maintenance' then 'bg-warning'
    when 'overdue' then 'bg-danger'
    else 'bg-secondary'
    end
  end
  
  def status_display
    case status
    when 'active' then 'Active'
    when 'maintenance' then 'In Maintenance'
    when 'overdue' then 'Overdue Maintenance'
    else 'Unknown'
    end
  end

  # ------------------------------------------------------------
  # Maintenance helpers
  # ------------------------------------------------------------
  def overdue_maintenances
    maintenances.overdue
  end

  def upcoming_maintenances
    maintenances.upcoming
  end

  def active_maintenances
    maintenances.active
  end

  def completed_maintenances
    maintenances.completed
  end

  def has_overdue_maintenance?
    overdue_maintenances.exists?
  end

  def has_active_maintenance?
    active_maintenances.exists?
  end

  def next_maintenance_date
    maintenances.pending.where.not(start_date: nil).minimum(:start_date)
  end

  def maintenance_status_summary
    {
      total: maintenances.count,
      pending: maintenances.pending.count,
      completed: maintenances.completed.count,
      overdue: overdue_maintenances.count,
      active: active_maintenances.count,
      upcoming: upcoming_maintenances.count
    }
  end

  # ------------------------------------------------------------
  # Driver helpers
  # ------------------------------------------------------------
  def current_driver_name
    driver&.name || 'Unassigned'
  end

  # ------------------------------------------------------------
  # Gantt Chart / Timeline Helpers
  # ------------------------------------------------------------
  def gantt_task_data(maintenances_for_vehicle = nil)
    vehicle_maintenances = maintenances_for_vehicle || maintenances
    dated_maintenances = vehicle_maintenances.select { |m| m.start_date && m.end_date }
    return nil if dated_maintenances.empty?

    start_dates = dated_maintenances.map(&:start_date)
    end_dates   = dated_maintenances.map(&:end_date)
    return nil if start_dates.empty? || end_dates.empty?

    {
      id: "vehicle_#{id}",
      name: "#{make} #{model} (#{registration_or_plate})",
      start: start_dates.min.to_s,
      end: end_dates.max.to_s,
      parent: "0",
      type: 'vehicle',
      color: '#6c757d',
      details: {
        service_owner: service_owner_display,
        agency: agency&.name,
        registration_number: registration_or_plate,
        current_driver: current_driver_name,
        license_plate: license_plate,
        vehicle_type: vehicle_type,
        maintenance_count: dated_maintenances.count
      }
    }
  end

  def gantt_maintenance_tasks
    maintenances.where.not(start_date: nil).where.not(end_date: nil).map(&:gantt_task_data).compact
  end

  def gantt_color_for_status
    if has_overdue_maintenance?
      '#dc3545'
    elsif has_active_maintenance?
      '#0dcaf0'
    elsif upcoming_maintenances.exists?
      '#ffc107'
    else
      '#6c757d'
    end
  end

  def timeline_events(start_date: Date.today - 30.days, end_date: Date.today + 90.days)
    events = []

    maintenances.where('start_date IS NOT NULL AND start_date <= ? AND end_date >= ?', 
                      end_date, start_date).each do |m|
      events << {
        id: "maintenance_#{m.id}",
        title: m.service_type,
        start: m.start_date,
        end: m.end_date,
        color: m.gantt_bar_color,
        type: 'maintenance',
        data: m
      }
    end

    if registration_expiry_date.present?
      events << {
        id: "registration_#{id}",
        title: "Registration Renewal",
        start: registration_expiry_date - 30.days,
        end: registration_expiry_date,
        color: '#6610f2',
        type: 'registration'
      }
    end

    events.sort_by { |e| e[:start] }
  end

  # ------------------------------------------------------------
  # Display helpers
  # ------------------------------------------------------------
  def display_name
    "#{license_plate} - #{make} #{model}"
  end

  def full_display_name
    "#{make} #{model} (#{registration_or_plate})"
  end

  def display_with_owner
    "#{make} #{model} (#{registration_or_plate}) - #{service_owner_display}"
  end

  def display_with_agency
    "#{make} #{model} (#{license_plate}) - #{agency&.name}"
  end

  # Simple display name without plate
  def simple_display_name
    [make, model].compact.join(" ")
  end

  # ------------------------------------------------------------
  # Search scope
  # ------------------------------------------------------------
  scope :search, ->(query) {
    return all if query.blank?
    where("make ILIKE :q OR model ILIKE :q OR license_plate ILIKE :q OR registration_number ILIKE :q", q: "%#{query}%")
  }

  # ------------------------------------------------------------
  # Usage analytics helper
  # ------------------------------------------------------------
  def usage_stats(from:, to:)
    trips_in_range = trips.where(start_time: from.beginning_of_day..to.end_of_day)
    distance_sum = trips_in_range.sum(:distance_km).to_f
    hours_sum    = trips_in_range.pluck(:id).sum { |id| Trip.find(id).duration_hours.to_f }
    trip_count   = trips_in_range.count

    total_days = [(to - from + 1).to_i, 1].max
    utilization = ((hours_sum / (total_days * 24.0)) * 100).round(1)

    {
      name: "#{make} #{model} (#{registration_or_plate || 'N/A'})",
      agency: agency&.name,
      distance_km: distance_sum,
      hours_plied: hours_sum,
      trip_count: trip_count,
      utilization_percent: utilization,
      maintenance_status: maintenance_status_summary
    }
  end

  # ------------------------------------------------------------
  # Validation status for UI
  # ------------------------------------------------------------
  def validation_status
    issues = []
    issues << "No maintenances scheduled" if maintenances.empty?
    issues << "No driver assigned" if driver.blank?
    issues << "Overdue maintenance" if has_overdue_maintenance?
    issues << "No agency assigned" if agency.blank?

    if issues.empty?
      { status: 'good', message: 'All good' }
    elsif issues.include?("Overdue maintenance")
      { status: 'danger', message: 'Overdue maintenance' }
    else
      { status: 'warning', message: issues.first }
    end
  end
  
  # ------------------------------------------------------------
  # Check if vehicle is available for assignment
  # ------------------------------------------------------------
  def available_for_assignment?(current_driver_id = nil)
    !has_active_maintenance? && (driver_id.nil? || driver_id == current_driver_id)
  end

  # ------------------------------------------------------------
  # Vehicle Health & Analytics
  # ------------------------------------------------------------
  
  # Generate QR code URL
  def qr_code_url
    nil # Placeholder for QR code implementation
  end
  
  # Fuel status helper
  def fuel_status
    return 'unknown' unless fuel_level.present?
    
    case fuel_level
    when 0..10 then 'critical'
    when 11..20 then 'low'
    when 21..50 then 'medium'
    else 'good'
    end
  end
  
  # Utilization calculation
  def calculate_utilization(from: 30.days.ago.to_date, to: Date.today)
    trips_in_range = trips.where(start_time: from.beginning_of_day..to.end_of_day)
    hours_sum = trips_in_range.sum(:duration_hours).to_f
    total_days = (to - from + 1).to_i
    
    ((hours_sum / (total_days * 24.0)) * 100).round(1)
  end
  
  # Maintenance overdue check
  def maintenance_overdue?
    maintenances.pending.where('next_due_date < ?', Date.today).exists?
  end
  
  # Service due in days
  def days_until_next_service
    next_service = maintenances.pending.where('next_due_date >= ?', Date.today)
                              .order(:next_due_date).first
    return nil unless next_service&.next_due_date
    
    (next_service.next_due_date - Date.today).to_i
  end
  
  # Health score (0-100)
  def health_score
    score = 100
    
    # Deduct for overdue maintenance
    score -= 20 if maintenance_overdue?
    
    # Deduct for low fuel
    score -= 10 if fuel_level.present? && fuel_level < 20
    
    # Deduct for active maintenance
    score -= 15 if has_active_maintenance?
    
    # Deduct for no recent trips (idle)
    if trips.where('start_time > ?', 7.days.ago).none?
      score -= 5
    end
    
    # Deduct for missing agency
    score -= 5 if agency.blank?
    
    [score, 0].max
  end
  
  # Return health status with color class
  def health_status
    score = health_score
    
    case score
    when 80..100 then 'excellent'
    when 60..79 then 'good'
    when 40..59 then 'fair'
    when 20..39 then 'poor'
    else 'critical'
    end
  end

  # Health status badge class
  def health_status_badge_class
    case health_status
    when 'excellent' then 'bg-success'
    when 'good' then 'bg-info'
    when 'fair' then 'bg-warning'
    when 'poor' then 'bg-danger'
    when 'critical' then 'bg-dark'
    else 'bg-secondary'
    end
  end
  
  # Quick stats for dashboard
  def quick_stats
    {
      total_trips: trips.count,
      total_distance: trips.sum(:distance_km).to_f.round(1),
      total_hours: trips.sum(:duration_hours).to_f.round(1),
      avg_trip_distance: trips.average(:distance_km).to_f.round(1),
      avg_trip_duration: trips.average(:duration_hours).to_f.round(1),
      last_trip_date: trips.order(start_time: :desc).first&.start_time,
      maintenance_count: maintenances.count,
      last_maintenance_date: maintenances.order(date: :desc).first&.date,
      health_score: health_score,
      health_status: health_status,
      fuel_status: fuel_status,
      utilization: calculate_utilization,
      agency: agency&.name
    }
  end

  # ------------------------------------------------------------
  # Additional useful methods
  # ------------------------------------------------------------
  
  # Calculate fuel efficiency if you track fuel consumption
  def fuel_efficiency
    return nil unless fuel_consumed.present? && trips.any?
    
    total_distance = trips.sum(:distance_km).to_f
    (total_distance / fuel_consumed).round(2) if fuel_consumed > 0
  end
  
  # Calculate total maintenance cost
  def total_maintenance_cost
    maintenances.sum(:cost).to_f
  end
  
  # Average maintenance cost per month
  def avg_monthly_maintenance_cost
    return 0 if maintenances.empty?
    
    first_maintenance = maintenances.order(:date).first.date
    months = ((Date.today - first_maintenance).to_i / 30.0).ceil
    months = 1 if months < 1
    
    (total_maintenance_cost / months).round(2)
  end
  
  # Vehicle age in years
  def age_in_years
    return nil unless year_of_manufacture.present?
    Date.today.year - year_of_manufacture
  end
  
  # ============================================================
  # INSURANCE METHODS - SAFE VERSION
  # ============================================================
  
  # Safe attribute reader/writer for insurance expiry date
  def insurance_expiry_date
    # Check if column exists in database
    if insurance_column_exists?
      self[:insurance_expiry_date]
    else
      # Return a default date for now (1 year from creation)
      @_temporary_insurance_date ||= (created_at || Time.current).to_date + 1.year
    end
  end
  
  def insurance_expiry_date=(value)
    # Only set if column exists
    if insurance_column_exists?
      self[:insurance_expiry_date] = value
    else
      @_temporary_insurance_date = value
    end
  end
  
  # Check if insurance column exists in database
  def insurance_column_exists?
    self.class.column_names.include?('insurance_expiry_date')
  end
  
  # Check if we have insurance data
  def has_insurance_data?
    insurance_expiry_date.present?
  end
  
  # Check if insurance is expired - safe version
  def insurance_expired?
    return false unless has_insurance_data?
    insurance_expiry_date < Date.today
  end
  
  # Check if insurance expires soon (within 30 days)
  def insurance_expiring_soon?
    return false unless has_insurance_data?
    insurance_expiry_date >= Date.today && insurance_expiry_date <= Date.today + 30.days
  end
  
  # Days until insurance expires
  def days_until_insurance_expiry
    return nil unless has_insurance_data?
    (insurance_expiry_date - Date.today).to_i
  end
  
  # Get insurance status
  def insurance_status
    return :no_data unless has_insurance_data?
    
    if insurance_expired?
      :expired
    elsif insurance_expiring_soon?
      :expiring_soon
    else
      :active
    end
  end
  
  # Get insurance status badge class
  def insurance_status_badge_class
    case insurance_status
    when :expired then 'bg-danger'
    when :expiring_soon then 'bg-warning'
    when :active then 'bg-success'
    else 'bg-secondary'
    end
  end
  
  # Get insurance status display text
  def insurance_status_display
    case insurance_status
    when :expired then 'Expired'
    when :expiring_soon then 'Expiring Soon'
    when :active then 'Active'
    else 'No Insurance Data'
    end
  end
  
  # Format insurance expiry date for display
  def insurance_expiry_display
    return 'No insurance data' unless has_insurance_data?
    
    if insurance_expired?
      "Expired on #{insurance_expiry_date.strftime('%B %d, %Y')}"
    elsif insurance_expiring_soon?
      days = days_until_insurance_expiry
      "Expires in #{days} #{'day'.pluralize(days)} on #{insurance_expiry_date.strftime('%B %d, %Y')}"
    else
      "Expires on #{insurance_expiry_date.strftime('%B %d, %Y')}"
    end
  end
  
  # Calculate downtime days (days in maintenance)
  def total_downtime_days
    maintenances.where(status: 'Completed').sum { |m| 
      (m.end_date - m.start_date).to_i + 1 if m.start_date && m.end_date
    }.to_i
  end
  
  # Calculate operational efficiency
  def operational_efficiency(from: 30.days.ago.to_date, to: Date.today)
    total_days = (to - from + 1).to_i
    downtime_days = total_downtime_days
    
    return 100 if downtime_days == 0
    ((total_days - downtime_days).to_f / total_days * 100).round(1)
  end
  
  # Get upcoming inspections
  def upcoming_inspections
    maintenances.where(service_type: 'Inspection')
                .where('next_due_date >= ?', Date.today)
                .order(:next_due_date)
  end
  
  # ------------------------------------------------------------
  # Location methods for Alert integration
  # ------------------------------------------------------------
  def current_location
    self[:current_location] || self[:location] || self[:last_known_location] || 
    self[:garage_location] || self[:depot] || self[:home_depot] ||
    agency&.name || "#{make} #{model} (#{license_plate})"
  end
  
  def last_known_location
    current_location
  end
  
  def location
    current_location
  end
  
  # ------------------------------------------------------------
  # Alert-related methods for better integration
  # ------------------------------------------------------------
  
  def active_alerts
    alerts.active_alerts
  end
  
  def critical_alerts
    alerts.critical_alerts
  end
  
  def urgent_alerts
    alerts.urgent_alerts
  end
  
  def needs_attention_alerts
    alerts.needs_attention
  end
  
  def has_active_alerts?
    active_alerts.any?
  end
  
  def has_critical_alerts?
    critical_alerts.any?
  end
  
  def has_urgent_alerts?
    urgent_alerts.any?
  end
  
  def alert_based_health_score
    base_score = 100
    base_score -= (needs_attention_alerts.count * 20)
    base_score -= (active_alerts.count * 5)
    [base_score, 0].max
  end
  
  # Combined health score that considers both vehicle issues and alerts
  def comprehensive_health_score
    vehicle_score = health_score
    alert_score = alert_based_health_score
    ((vehicle_score + alert_score) / 2).round
  end
  
  def alert_summary
    {
      total_alerts: alerts.count,
      active_alerts: active_alerts.count,
      critical_alerts: critical_alerts.count,
      urgent_alerts: urgent_alerts.count,
      needs_attention: needs_attention_alerts.count,
      health_score: alert_based_health_score,
      needs_immediate_attention: needs_immediate_attention?
    }
  end
  
  # Check if vehicle needs immediate attention (UPDATED with alerts)
  def needs_immediate_attention?
    return true if alerts.any?(&:needs_attention?)
    
    maintenance_overdue? || 
    (fuel_level.present? && fuel_level < 10) ||
    insurance_expired? ||
    health_status == 'critical'
  end
  
  # Get vehicle efficiency rating (A-F)
  def efficiency_rating
    utilization = calculate_utilization
    op_efficiency = operational_efficiency
    
    avg_score = (utilization + op_efficiency) / 2
    
    case avg_score
    when 90..100 then 'A'
    when 80..89 then 'B'
    when 70..79 then 'C'
    when 60..69 then 'D'
    when 50..59 then 'E'
    else 'F'
    end
  end
  
  # Vehicle readiness score (0-10)
  def readiness_score
    score = 10
    
    # Deductions for issues
    score -= 3 if needs_immediate_attention?
    score -= 2 if has_active_maintenance?
    score -= 1 if fuel_level.present? && fuel_level < 30
    score -= 1 if driver.blank?
    score -= 1 if agency.blank?
    
    [score, 0].max
  end
  
  # Summary for dashboard cards
  def dashboard_summary
    {
      id: id,
      name: display_name,
      license_plate: license_plate,
      status: status_display,
      status_class: status_badge_class,
      health_score: comprehensive_health_score,
      health_status: health_status,
      health_class: health_status_badge_class,
      driver: current_driver_name,
      last_maintenance: maintenances.order(date: :desc).first&.date,
      next_maintenance: next_maintenance_date,
      fuel_level: fuel_level,
      fuel_status: fuel_status,
      needs_attention: needs_immediate_attention?,
      efficiency_rating: efficiency_rating,
      readiness_score: readiness_score,
      agency: agency&.name,
      alert_summary: alert_summary
    }
  end
  
  # Create a new alert for this vehicle
  def create_alert(params)
    alerts.create!(params.merge(
      vehicle_id: id,
      location: current_location,
      agency_id: agency_id
    ))
  end
  
  # Create a critical incident for this vehicle
  def create_critical_incident(title:, description:, **opts)
    Alert.create_critical_incident(
      title: title,
      description: description,
      vehicle_id: id,
      location: current_location,
      agency_id: agency_id,
      **opts
    )
  end
  
  # Create a maintenance alert for this vehicle
  def create_maintenance_alert(description, priority = 'high_priority')
    Alert.create_maintenance_alert(
      self,
      description,
      priority
    )
  end
  
  # Resolve all active alerts for this vehicle
  def resolve_all_alerts(resolution_notes = "All alerts resolved")
    active_alerts.each do |alert|
      alert.resolve!(resolution_notes)
    end
  end
  
  # Get alerts that need immediate attention
  def urgent_alerts_needing_action
    needs_attention_alerts
  end
  
  # Check if vehicle has any unresolved alerts
  def has_unresolved_alerts?
    alerts.unresolved.any?
  end
  
  # Get alert statistics for dashboard
  def alert_statistics
    {
      total: alerts.count,
      active: active_alerts.count,
      critical: critical_alerts.count,
      urgent: urgent_alerts.count,
      needs_attention: needs_attention_alerts.count,
      resolved: alerts.resolved.count,
      acknowledged: alerts.acknowledged.count,
      recent_24h: alerts.where('created_at >= ?', 24.hours.ago).count
    }
  end
  
  # Get recent alert activity (last 7 days)
  def recent_alert_activity(days: 7)
    alerts.where('created_at >= ?', days.days.ago)
          .group_by_day(:created_at)
          .count
  end
  
  # Get alert severity distribution
  def alert_severity_distribution
    alerts.group(:severity).count
  end
  
  # Get alert type distribution
  def alert_type_distribution
    alerts.group(:alert_type).count
  end
  
  # ------------------------------------------------------------
  # NEW METHODS FOR DASHBOARD DISPLAY
  # ------------------------------------------------------------
  
  # Short display for dashboard table
  def short_display
    if has_active_alerts?
      if needs_attention_alerts.any?
        '🚨'
      else
        '⚠️'
      end
    else
      '✅'
    end
  end
  
  # Quick stats for dashboard (simplified version)
  def dashboard_stats
    {
      display_name: display_name,
      license_plate: license_plate,
      status: status_display,
      status_class: status_badge_class,
      health_score: comprehensive_health_score,
      health_status: health_status,
      health_class: health_status_badge_class,
      driver: current_driver_name,
      fuel_level: fuel_level,
      fuel_status: fuel_status,
      needs_attention: needs_immediate_attention?,
      alert_count: active_alerts.count,
      critical_alert_count: critical_alerts.count,
      agency: agency&.name
    }
  end
  
  # Helper method for status check with alerts
  def status_with_alerts
    if needs_immediate_attention?
      'needs_attention'
    else
      status
    end
  end
  
  # Color coding for status with alerts
  def status_with_alerts_badge_class
    if needs_immediate_attention?
      'bg-danger'
    else
      status_badge_class
    end
  end
  
  # Display status with alert indicators
  def status_with_alerts_display
    if needs_immediate_attention?
      "Needs Attention"
    else
      status_display
    end
  end
  
  # Simple alert presence indicator
  def has_alerts?
    alerts.any?
  end
  
  # Alert severity level
  def highest_alert_severity
    return 'none' unless has_active_alerts?
    
    if critical_alerts.any?
      'critical'
    elsif urgent_alerts.any?
      'urgent'
    elsif active_alerts.any?
      'warning'
    else
      'none'
    end
  end
  
  # Dashboard card data
  def dashboard_card_data
    {
      id: id,
      name: display_name,
      license_plate: license_plate,
      status: status_with_alerts_display,
      status_class: status_with_alerts_badge_class,
      health_score: comprehensive_health_score,
      health_class: health_status_badge_class,
      driver: current_driver_name,
      alerts_count: active_alerts.count,
      critical_alerts_count: critical_alerts.count,
      needs_attention: needs_immediate_attention?,
      short_display: short_display,
      highest_alert: highest_alert_severity,
      agency: agency&.name,
      agency_code: agency&.code
    }
  end
  
  # Quick health assessment
  def health_assessment
    score = comprehensive_health_score
    
    case score
    when 90..100
      { level: 'excellent', message: 'Vehicle in excellent condition', color: 'success' }
    when 70..89
      { level: 'good', message: 'Vehicle in good condition', color: 'info' }
    when 50..69
      { level: 'fair', message: 'Vehicle requires attention soon', color: 'warning' }
    when 30..49
      { level: 'poor', message: 'Vehicle needs immediate attention', color: 'danger' }
    else
      { level: 'critical', message: 'Vehicle requires emergency attention', color: 'dark' }
    end
  end
  
  # Alert summary for quick view
  def alert_quick_summary
    {
      has_alerts: has_active_alerts?,
      alert_count: active_alerts.count,
      critical_count: critical_alerts.count,
      urgent_count: urgent_alerts.count,
      needs_attention: needs_immediate_attention?,
      highest_severity: highest_alert_severity,
      summary: "#{active_alerts.count} active alert#{active_alerts.count == 1 ? '' : 's'}"
    }
  end
  
  # ------------------------------------------------------------
  # INVOICE-RELATED METHODS
  # ------------------------------------------------------------
  
  # Get all invoices for this vehicle
  def vehicle_invoices
    Invoice.where(vehicle_id: id)
  end
  
  # Get pending invoices for this vehicle
  def pending_invoices
    vehicle_invoices.where(status: ['pending_review', 'pending_payment'])
  end
  
  # Get overdue invoices for this vehicle
  def overdue_invoices
    vehicle_invoices.overdue
  end
  
  # Get paid invoices for this vehicle
  def paid_invoices
    vehicle_invoices.paid
  end
  
  # Total invoice amount for this vehicle
  def total_invoice_amount
    vehicle_invoices.sum(:amount)
  end
  
  # Pending invoice amount for this vehicle
  def pending_invoice_amount
    pending_invoices.sum(:amount)
  end
  
  # Check if vehicle has any pending invoices
  def has_pending_invoices?
    pending_invoices.any?
  end
  
  # Check if vehicle has any overdue invoices
  def has_overdue_invoices?
    overdue_invoices.any?
  end
  
  # Invoice summary for dashboard
  def invoice_summary
    {
      total_invoices: vehicle_invoices.count,
      pending_invoices: pending_invoices.count,
      overdue_invoices: overdue_invoices.count,
      paid_invoices: paid_invoices.count,
      total_amount: total_invoice_amount,
      pending_amount: pending_invoice_amount,
      has_pending: has_pending_invoices?,
      has_overdue: has_overdue_invoices?
    }
  end
  
  # ------------------------------------------------------------
  # AGENCY-SPECIFIC METHODS
  # ------------------------------------------------------------
  
  def is_ptsc_vehicle?
    agency&.code == 'PTSC'
  end
  
  def is_ttps_vehicle?
    agency&.code == 'TTPS'
  end
  
  def is_ttdf_vehicle?
    agency&.code == 'TTDF'
  end
  
  def is_fire_vehicle?
    agency&.code == 'FIRE'
  end
  
  def is_health_vehicle?
    agency&.code == 'HEALTH'
  end
  
  def is_education_vehicle?
    agency&.code == 'EDUCATION'
  end
  
  def is_vmcott_vehicle?
    agency&.code == 'VMCOTT'
  end
  
  # Check if vehicle belongs to a specific agency
  def belongs_to_agency?(agency_code)
    agency&.code == agency_code
  end
  
  # Get agency-specific badge class
  def agency_badge_class
    return 'bg-secondary' unless agency
    
    case agency.code
    when 'PTSC' then 'bg-ptsc'
    when 'TTPS' then 'bg-police'
    when 'TTDF' then 'bg-military'
    when 'FIRE' then 'bg-fire'
    when 'HEALTH' then 'bg-success'
    when 'EDUCATION' then 'bg-info'
    when 'VMCOTT' then 'bg-warning'
    else 'bg-secondary'
    end
  end
  
  # ------------------------------------------------------------
  # FINANCIAL METHODS
  # ------------------------------------------------------------
  
  # Calculate total cost of ownership (maintenance + invoices)
  def total_cost_of_ownership
    total_maintenance_cost + total_invoice_amount
  end
  
  # Calculate cost per mile/kilometer
  def cost_per_km
    total_distance = trips.sum(:distance_km).to_f
    return 0 if total_distance == 0
    (total_cost_of_ownership / total_distance).round(2)
  end
  
  # Calculate monthly operating cost
  def monthly_operating_cost
    first_trip = trips.order(start_time: :asc).first
    return 0 unless first_trip
    
    months = ((Date.today - first_trip.start_time.to_date).to_i / 30.0).ceil
    months = 1 if months < 1
    
    (total_cost_of_ownership / months).round(2)
  end
end