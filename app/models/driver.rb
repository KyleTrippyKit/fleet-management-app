class Driver < ApplicationRecord
  STATUSES = %w[active suspended inactive].freeze

  # ============================================================
  # Associations
  # ============================================================
  
  # Historical vehicle usage (do NOT destroy history automatically)
  has_many :vehicle_usages, dependent: :restrict_with_error
  has_many :vehicles, through: :vehicle_usages

  # Vehicles currently assigned to the driver (vehicle_usages with no end_date)
  has_many :assigned_vehicles,
           -> { where(vehicle_usages: { end_date: nil }) },
           through: :vehicle_usages,
           source: :vehicle

  # Trips by this driver
  has_many :trips, dependent: :nullify

  # Optional future-proofing
  has_many :damage_reports, dependent: :nullify

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

  # Display names of currently assigned vehicles
  def assigned_vehicle_names
    assigned_vehicles.pluck(:registration_number).join(", ")
  end
end