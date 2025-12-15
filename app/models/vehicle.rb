class Vehicle < ApplicationRecord
  # ------------------------------------------------------------
  # Associations
  # ------------------------------------------------------------

  # A vehicle can have many maintenance records.
  # If a vehicle is deleted, all its maintenances are deleted too.
  has_many :maintenances, dependent: :destroy

  # Logs that track usage over time (e.g., hours, distance)
  has_many :usage_logs, dependent: :destroy

  # Trips made by this vehicle
  has_many :trips, dependent: :destroy

  # Uploaded documents (insurance, inspection, etc.)
  has_many :vehicle_documents, dependent: :destroy

  # Current driver assignment
  belongs_to :driver, optional: true

  # Historical usage
  has_many :vehicle_usages, dependent: :destroy
  has_many :drivers, through: :vehicle_usages

  # ------------------------------------------------------------
  # ActiveStorage attachments
  # ------------------------------------------------------------
  has_one_attached :image        # Main image for cards/listings
  has_one_attached :picture      # Optional alternative picture
  has_many_attached :gallery_images # Optional gallery

  # ------------------------------------------------------------
  # Trinidad & Tobago license plate rules
  # ------------------------------------------------------------
  TT_PRIMARY_PREFIXES = %w[P H T G].freeze  # Standard plate letters
  TT_SPECIAL_PREFIXES = %w[CD RR D R].freeze # Government/diplomatic

  # Normalize license plate before validation
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
end
