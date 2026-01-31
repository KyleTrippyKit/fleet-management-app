# app/models/vehicle_catalog_entry.rb
class VehicleCatalogEntry < ApplicationRecord
  validates :make, :model, presence: true
  validates :model, uniqueness: { scope: :make }

  scope :search, ->(q) {
    return all if q.blank?
    where("make ILIKE :q OR model ILIKE :q", q: "%#{q}%")
      .order(:make, :model)
  }

  def label
    "#{make} #{model}"
  end
end
