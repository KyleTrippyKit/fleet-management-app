class Maintenance < ApplicationRecord
  belongs_to :vehicle
  belongs_to :assigned_to, class_name: "User", optional: true
  belongs_to :service_provider # ✅ new association
  has_many :maintenance_tasks, dependent: :destroy

  # Valid assignment types
  ASSIGNMENT_TYPES = %w[stores purchasing].freeze

  # Valid statuses
  STATUSES = %w[Pending Completed].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :assignment_type, inclusion: { in: ASSIGNMENT_TYPES }, presence: true
  validates :service_provider, presence: true # ensure every maintenance has a provider

  # Helpers to mimic enum-style methods without using enum
  def assignment_type_stores?
    assignment_type == "stores"
  end

  def assignment_type_purchasing?
    assignment_type == "purchasing"
  end

  # Determine urgency badge text based on assignment type and part stock
  def urgency_label
    if assignment_type_stores? && part_in_stock
      "Fast"
    else
      "Soon"
    end
  end

  # Optional helper for next service mileage
  def mileage_until_next_service(interval = 5000)
    return unless mileage && vehicle&.mileage

    last_mileage = self.mileage
    next_service_mileage = last_mileage + interval
    next_service_mileage - vehicle.mileage
  end
end
