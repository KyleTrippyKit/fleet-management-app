class Vehicle < ApplicationRecord
  # ------------------------------------------------------------
  # Associations
  # ------------------------------------------------------------
  has_many :maintenances, dependent: :destroy
  has_many :trips, dependent: :destroy
  has_many :drivers, through: :trips
  has_many :vehicle_documents, dependent: :destroy

  belongs_to :driver, optional: true

  # ActiveStorage attachments
  has_one_attached :image
  has_one_attached :picture
  has_many_attached :gallery_images

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
  # Maintenance helpers
  # ------------------------------------------------------------
  def overdue_maintenances
    maintenances.overdue
  end

  def upcoming_maintenances
    maintenances.upcoming
  end

  def has_overdue_maintenance?
    overdue_maintenances.exists?
  end

  # ------------------------------------------------------------
  # Display helpers
  # ------------------------------------------------------------
  def display_name
    "#{make} - #{license_plate}"
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
    where("make ILIKE :q OR model ILIKE :q OR license_plate ILIKE :q", q: "%#{query}%")
  }

  # ------------------------------------------------------------
  # Usage analytics helper
  # ------------------------------------------------------------
  def usage_stats(from:, to:)
    trips_in_range = trips.where(start_time: from.beginning_of_day..to.end_of_day)

    # Use pluck + sum to avoid calling method on ActiveRecord relation
    distance_sum = trips_in_range.sum(:distance_km).to_f
    hours_sum    = trips_in_range.pluck(:id).sum { |id| Trip.find(id).duration_hours.to_f }
    trip_count   = trips_in_range.count

    total_days = [(to - from + 1).to_i, 1].max # prevent division by zero
    utilization = ((hours_sum / (total_days * 24.0)) * 100).round(1)

    {
      name: "#{make} #{model} (#{registration_number || 'N/A'})",
      distance_km: distance_sum,
      hours_plied: hours_sum,
      trip_count: trip_count,
      utilization_percent: utilization
    }
  end
end
