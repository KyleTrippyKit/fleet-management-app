class ServiceProvider < ApplicationRecord
  PROVIDER_TYPES = %w[internal_workshop external_contractor].freeze

  validates :name, presence: true
  validates :provider_type, inclusion: { in: PROVIDER_TYPES }

  scope :active, -> { where(is_active: true) }
  scope :internal_workshops, -> { where(provider_type: "internal_workshop") }
  scope :external_contractors, -> { where(provider_type: "external_contractor") }

  def internal_workshop?
    provider_type == "internal_workshop"
  end
end
