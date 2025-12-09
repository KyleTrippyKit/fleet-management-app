class VehicleDocument < ApplicationRecord
  belongs_to :vehicle
  has_one_attached :file
end
