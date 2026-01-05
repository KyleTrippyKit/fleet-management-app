class Driver < ApplicationRecord
  STATUSES = %w[active suspended inactive].freeze

  belongs_to :agency, optional: true
  # ============================================================
  # Associations
  # ============================================================
  has_many :vehicles, dependent: :nullify
  has_many :trips, dependent: :nullify
  has_many :damage_reports, dependent: :nullify
  
  # Comment out non-existent associations for now
  # has_many :maintenance_requests, dependent: :nullify
  # has_many :pre_trip_inspections, dependent: :nullify

  # ============================================================
  # Validations
  # ============================================================
  validates :name, presence: true
  validates :license_number, uniqueness: true, allow_blank: true
  validates :status, inclusion: { in: STATUSES }
  validates :contact_number, presence: true
  validates :employee_id, uniqueness: true, allow_blank: true

  # ============================================================
  # Scopes
  # ============================================================
  scope :active, -> { where(status: "active") }
  scope :inactive, -> { where.not(status: "active") }
  scope :available, -> { active.where.not(id: Vehicle.where.not(driver_id: nil).select(:driver_id)) }

  # ============================================================
  # Instance Methods
  # ============================================================
  def active?
    status == "active"
  end

  # Maintenance-related methods
  def maintenance_stats
    {
      reports_submitted: 0, # Placeholder until maintenance_requests exists
      open_issues: 0,
      resolved_issues: 0,
      damage_reports_count: damage_reports.count
    }
  end

  def recent_maintenance_requests(limit = 5)
    [] # Placeholder until maintenance_requests exists
  end

  def assigned_vehicles_display
    vehicles.map(&:display_name).join(", ") || "None assigned"
  end

  # Performance metrics for maintenance team
  def maintenance_performance
    {
      total_issues_reported: 0,
      avg_response_time_hours: 0,
      last_report_date: nil,
      currently_assigned: vehicles.count
    }
  end

  def calculate_avg_response_time
    0 # Placeholder
  end

  # Quick contact info for maintenance team
  def contact_info
    {
      name: name,
      phone: contact_number,
      emergency_contact: emergency_contact_name,
      emergency_phone: emergency_contact_phone,
      currently_driving: vehicles.first&.display_name
    }
  end

  # Display names of assigned vehicles
  def assigned_vehicle_names
    vehicles.pluck(:registration_number).join(", ")
  end

  # Historical vehicles - simple implementation for now
  def historical_vehicles
    []
  end

  # Current vehicles - all assigned vehicles
  def current_vehicles
    vehicles.to_a
  end

  # Compute usage stats for this driver
  def usage_stats(from: 30.days.ago.to_date, to: Date.today)
    trips_in_range = trips.where(start_time: from.beginning_of_day..to.end_of_day)

    distance_sum = trips_in_range.sum(:distance_km).to_f
    hours_sum    = trips_in_range.sum(&:duration_hours).to_f
    trip_count   = trips_in_range.count

    total_days = (to - from + 1).to_i
    utilization = total_days.positive? ? ((hours_sum / (total_days * 24.0)) * 100).round(1) : 0

    {
      distance_km: distance_sum,
      hours_plied: hours_sum,
      trip_count: trip_count,
      utilization_percent: utilization
    }
  end
end