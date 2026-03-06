# app/models/vehicle_condition_report.rb
class VehicleConditionReport < ApplicationRecord
  belongs_to :vehicle
  belongs_to :reception_log
  belongs_to :security_officer, class_name: 'User'
  
  has_many_attached :condition_photos
  
  # Core fields only
  validates :fuel_level, numericality: { in: 0..100 }
  validates :odometer, numericality: { greater_than: 0 }
  
  # Simple JSON field for all condition data
  store_accessor :condition_data, 
    :exterior_damage,    # array: ['scratches', 'dents', 'paint', 'glass']
    :interior_issues,    # array: ['dirty', 'seat_damage', 'odor']
    :tire_status,        # string: 'good', 'low_pressure', 'damage'
    :warning_lights,     # array: ['check_engine', 'other']
    :notes                # text
  
  # Signature
  store_accessor :acknowledgment, 
    :driver_name, 
    :signature_data,
    :signed_at
end