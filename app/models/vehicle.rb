# app/models/vehicle.rb
class Vehicle < ApplicationRecord
  # ------------------------------------------------------------
  # Virtual attributes for form handling
  # ------------------------------------------------------------
  attr_accessor :remove_primary_photo
  
  # ------------------------------------------------------------
  # Associations
  # ------------------------------------------------------------
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

  before_validation :normalize_license_plate

  # ------------------------------------------------------------
  # Validations
  # ------------------------------------------------------------
  validates :make, :model, :vehicle_type, :license_plate, :registration_number, presence: true
  validates :chassis_number, :serial_number, :year_of_manufacture, presence: true
  validates :license_plate, :registration_number, uniqueness: true
  validates :service_owner, presence: true, inclusion: { in: ["PTSC", "Police", "Fire Service"] }

  validates :license_plate, format: {
    with: /\A([A-Z]{3}|CD|RR|D|R)-\d{1,4}\z/,
    message: "must follow Trinidad format (ABC-1234)"
  }

  # ------------------------------------------------------------
  # Scopes for filtering
  # ------------------------------------------------------------
  scope :by_service_owner, ->(owner) { where(service_owner: owner) if owner.present? }
  scope :by_type, ->(type) { where(vehicle_type: type) if type.present? }
  scope :with_active_maintenance, -> { joins(:maintenances).where(maintenances: { status: 'Pending' }).distinct }
  
  # NEW: Active vehicles available for assignment
  # Vehicles that are not in active maintenance and not assigned to other drivers
  scope :active, -> {
    # Vehicles that don't have active/pending maintenance and are either unassigned or assigned to current driver
    left_joins(:maintenances)
      .where("maintenances.status IS NULL OR maintenances.status NOT IN (?)", ['Pending', 'In Progress'])
      .distinct
  }
  
  # Available for assignment (not assigned to any driver OR assigned to specific driver for editing)
  scope :available_for_assignment, ->(current_driver_id = nil) {
    if current_driver_id
      # Include vehicles assigned to this driver (for editing) plus unassigned vehicles
      where("driver_id IS NULL OR driver_id = ?", current_driver_id)
    else
      # Only unassigned vehicles for new assignments
      where(driver_id: nil)
    end
  }

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
    # Use asset_path for asset pipeline images
    ActionController::Base.helpers.asset_path(asset_image_path)
  end

  def display_image
    # Priority 1: User uploaded primary photo
    if primary_photo.attached?
      primary_photo
    # Priority 2: Asset pipeline placeholder
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
    # Return a default value or implement your logic
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
      name: "#{make} #{model} (#{registration_number})",
      start: start_dates.min.to_s,
      end: end_dates.max.to_s,
      parent: "0",
      type: 'vehicle',
      color: '#6c757d',
      details: {
        service_owner: service_owner,
        registration_number: registration_number,
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
    "#{make} #{model} - #{license_plate}"
  end

  def full_display_name
    "#{make} #{model} (#{registration_number})"
  end

  def display_with_owner
    "#{make} #{model} (#{registration_number}) - #{service_owner}"
  end

  # ------------------------------------------------------------
  # License plate normalization
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
      name: "#{make} #{model} (#{registration_number || 'N/A'})",
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
    # Vehicle is available if:
    # 1. It doesn't have active/pending maintenance
    # 2. It's either unassigned OR assigned to the current driver (for editing)
    !has_active_maintenance? && (driver_id.nil? || driver_id == current_driver_id)
  end

  # ------------------------------------------------------------
  # NEW METHODS: Vehicle Health & Analytics
  # ------------------------------------------------------------
  
  # Generate QR code URL
  def qr_code_url
    # You'll need to install rqrcode gem and add:
    # require 'rqrcode'
    
    # qr = RQRCode::QRCode.new(Rails.application.routes.url_helpers.vehicle_url(self, host: ENV['BASE_URL']))
    # svg = qr.as_svg(offset: 0, color: '000', shape_rendering: 'crispEdges', module_size: 6)
    # "data:image/svg+xml;base64,#{Base64.strict_encode64(svg)}"
    
    # For now, return nil or placeholder
    nil
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
  
  # Utilization calculation (more efficient version)
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
      utilization: calculate_utilization
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
  
  # Check if insurance is expired
  def insurance_expired?
    return false unless insurance_expiry_date.present?
    insurance_expiry_date < Date.today
  end
  
  # Days until insurance expires
  def days_until_insurance_expiry
    return nil unless insurance_expiry_date.present?
    (insurance_expiry_date - Date.today).to_i
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
  
  # Check if vehicle needs immediate attention
  def needs_immediate_attention?
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
      health_score: health_score,
      health_status: health_status,
      health_class: health_status_badge_class,
      driver: current_driver_name,
      last_maintenance: maintenances.order(date: :desc).first&.date,
      next_maintenance: next_maintenance_date,
      fuel_level: fuel_level,
      fuel_status: fuel_status,
      needs_attention: needs_immediate_attention?,
      efficiency_rating: efficiency_rating,
      readiness_score: readiness_score
    }
  end
end