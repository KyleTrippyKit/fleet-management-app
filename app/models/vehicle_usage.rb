class VehicleUsage < ApplicationRecord
  belongs_to :driver
  belongs_to :vehicle

  # ============================================================
  # Validations
  # ============================================================
  validates :driver_id, :vehicle_id, presence: true

  # Optionally add start_date if you want to track usage periods
  # attribute :start_date, :datetime, default: -> { Time.current }
end