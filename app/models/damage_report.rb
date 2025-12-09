class DamageReport < ApplicationRecord
  belongs_to :vehicle
  has_many_attached :photos
end
