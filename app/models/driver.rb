class Driver < ApplicationRecord
  STATUSES = %w[active suspended inactive].freeze

  # ============================================================
  # Associations
  # ============================================================
  has_many :trips, dependent: :nullify
  has_many :damage_reports, dependent: :nullify

  # Multi-vehicle assignment via a join table
  has_and_belongs_to_many :vehicles,
                          join_table: :drivers_vehicles,
                          association_foreign_key: :vehicle_id,
                          dependent: :nullify

  # ============================================================
  # Validations
  # ============================================================
  validates :name, presence: true
  validates :license_number, uniqueness: true, allow_blank: true
  validates :status, inclusion: { in: STATUSES }

  # ============================================================
  # Scopes
  # ============================================================
  scope :active, -> { where(status: "active") }
  scope :inactive, -> { where.not(status: "active") }

  # ============================================================
  # Instance Methods
  # ============================================================
  def active?
    status == "active"
  end

  # Display names of assigned vehicles
  def assigned_vehicle_names
    vehicles.pluck(:registration_number).join(", ")
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
