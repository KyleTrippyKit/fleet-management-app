class DamageReport < ApplicationRecord
  belongs_to :vehicle
  belongs_to :driver, optional: true
  
  has_many_attached :photos
end
