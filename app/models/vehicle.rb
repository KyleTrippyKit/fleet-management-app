class Vehicle < ApplicationRecord
  has_many :maintenances, dependent: :destroy
  has_many :usage_logs, dependent: :destroy
  has_many :trips, dependent: :destroy
  has_many :vehicle_documents, dependent: :destroy

  has_one_attached :image
  has_one_attached :picture
  has_many_attached :gallery_images

  # -----------------------------------------------------------------------------------
  # REAL TRINIDAD LICENSE PLATE SYSTEM — Updated for 3-letter prefixes (e.g. PAB-4521)
  # -----------------------------------------------------------------------------------

  # Categories based on Trinidad format
  TT_PRIMARY_PREFIXES = %w[
    P H T G
  ].freeze

  # Special non-3-letter formats
  TT_SPECIAL_PREFIXES = %w[
    CD RR D R
  ].freeze

  before_validation :normalize_license_plate

  validates :make, :model, :vehicle_type, :license_plate, :registration_number, presence: true
  validates :chassis_number, :serial_number, :year_of_manufacture, presence: true

  validates :license_plate, uniqueness: true
  validates :registration_number, uniqueness: true

  # Accept:
  #   - Standard TT: ABC-1234  (3 letters, 1–4 digits)
  #   - Special: CD-12, D-55, RR-8833
  validates :license_plate, format: {
    with: /\A([A-Z]{3}|CD|RR|D|R)-\d{1,4}\z/,
    message: "must follow Trinidad format (ABC-1234)"
  }

  validate :tt_prefix_must_be_valid

  VALID_OWNERS = ["PTSC", "Police", "Fire Service"].freeze
  validates :service_owner, presence: true, inclusion: { in: VALID_OWNERS }

  # -----------------------------------------------------------------------------------
  # Custom methods
  # -----------------------------------------------------------------------------------

  def display_name
    "#{make} - #{license_plate}"
  end

  # Normalize Trinidad plate formatting
  def normalize_license_plate
    return if license_plate.blank?

    plate = license_plate.to_s.strip.upcase
    plate = plate.gsub(/\s+/, "")
    plate = plate.gsub(/[^A-Z0-9]/, "")

    prefix = plate[/\A[A-Z]+/]
    numbers = plate[/\d+/]

    return if prefix.blank? || numbers.blank?

    # Truncate prefix to 3 letters if someone types too many
    if prefix.length > 3
      prefix = prefix[0, 3]
    end

    self.license_plate = "#{prefix}-#{numbers}"
  end

  # Validate TT prefixes
  def tt_prefix_must_be_valid
    return if license_plate.blank?

    prefix = license_plate.split("-").first

    # Special prefixes are allowed
    return if TT_SPECIAL_PREFIXES.include?(prefix)

    # Must be exactly 3 letters
    if prefix.length != 3
      errors.add(:license_plate, "prefix must be exactly 3 letters (e.g., PAB-, HCR-, TDM-)")
      return
    end

    # First letter must be a valid category
    unless TT_PRIMARY_PREFIXES.include?(prefix[0])
      errors.add(:license_plate, "must start with a valid Trinidad category (P, H, T, G)")
    end

    # Next two letters must be A–Z
    unless prefix[1..2] =~ /\A[A-Z]{2}\z/
      errors.add(:license_plate, "must use letters A–Z in the second and third positions")
    end
  end

  # -----------------------------------------------------------------------------------
  # Usage Stats
  # -----------------------------------------------------------------------------------

  def usage_stats(from:, to:, available_hours_per_day: 24)
    trips_in_range = trips.where("start_time >= ? AND end_time <= ?", from.beginning_of_day, to.end_of_day)
    total_hours = trips_in_range.sum { |t| t.duration_hours.to_f }
    total_distance = trips_in_range.sum { |t| t.distance_km.to_f }
    trip_count = trips_in_range.count

    days = (to - from).to_i + 1
    utilization_percent = days.positive? ? ((total_hours / (days * available_hours_per_day)) * 100).round(2) : 0

    daily_usage = (from..to).map do |day|
      day_trips = trips_in_range.where("start_time >= ? AND end_time <= ?", day.beginning_of_day, day.end_of_day)
      day_hours = day_trips.sum { |t| t.duration_hours.to_f }
      percent = available_hours_per_day.positive? ? ((day_hours / available_hours_per_day) * 100).round(1) : 0
      { date: day, hours: day_hours, percent: percent }
    end

    {
      name: display_name,
      service_owner: service_owner || "Unknown",
      trip_count: trip_count,
      distance_km: total_distance,
      hours_plied: total_hours,
      utilization_percent: utilization_percent,
      daily_usage: daily_usage
    }
  end

  scope :search, ->(query) {
    return all if query.blank?
    where("make ILIKE :q OR model ILIKE :q OR license_plate ILIKE :q", q: "%#{query}%")
  }
end
