# app/models/vehicle_condition_report.rb
# Model to store vehicle condition upon arrival at the gate
# Created by Security Gate Officer during vehicle check-in
# Requires driver signature for accountability

class VehicleConditionReport < ApplicationRecord
  # ========================
  # ASSOCIATIONS
  # ========================
  belongs_to :vehicle
  belongs_to :reception_log, optional: true
  belongs_to :security_gate_officer, class_name: 'User', foreign_key: 'security_officer_id'
  belongs_to :client, polymorphic: true, optional: true  # Can be Agency (PTSC) or Driver/Public
  
  # For active storage photos
  has_many_attached :condition_photos
  
  # ========================
  # VALIDATIONS
  # ========================
  validates :fuel_level, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :odometer, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :driver_name, presence: true, if: :signed?
  validates :signature_data, presence: true, if: :signed?
  validates :signed_at, presence: true, if: :signed?
  
  # ========================
  # STORE ACCESSORS - Simple JSON storage for condition data
  # ========================
  store_accessor :condition_data, 
    # Exterior damage (multiple selections allowed)
    :exterior_damage,           # array: ['scratches', 'dents', 'paint', 'glass', 'mirror', 'lights']
    :exterior_notes,            # text: location of specific damage
    
    # Interior condition (multiple selections allowed)
    :interior_issues,           # array: ['dirty', 'seat_damage', 'carpet_damage', 'dashboard_damage', 'odor']
    
    # Tire condition (single selection via radio)
    :tire_status,               # string: 'good', 'low_pressure', 'damage'
    :tire_notes,                # text: specific tire damage notes
    
    # Warning lights (multiple selections allowed)
    :warning_lights,            # array: ['none', 'check_engine', 'other']
    
    # Additional notes
    :additional_notes,          # text: any other observations
    
    # Photo checklist (which photos were taken)
    :photos_taken               # array: ['front', 'rear', 'left', 'right', 'dashboard', 'odometer', 'fuel_gauge', 'damage']
  
  # ========================
  # ACKNOWLEDGMENT STORAGE
  # ========================
  store_accessor :acknowledgment,
    :driver_name,
    :driver_id_number,          # Optional: driver's license / national ID
    :signature_data,            # Base64 encoded signature
    :signed_at,                 # Timestamp of signature
    :ip_address,                # For audit trail
    :user_agent                 # Browser info for audit
  
  # ========================
  # ENUMS
  # ========================
  enum :status, {
    draft: 'draft',
    completed: 'completed',
    disputed: 'disputed'
  }, default: 'draft'
  
  # ========================
  # CALLBACKS
  # ========================
  before_save :set_signed_at, if: :signature_data_changed?
  after_save :update_reception_log, if: :completed?
  
  # ========================
  # SCOPES
  # ========================
  scope :today, -> { where(created_at: Time.current.beginning_of_day..Time.current.end_of_day) }
  scope :for_vehicle, ->(vehicle) { where(vehicle: vehicle) }
  scope :completed, -> { where(status: 'completed') }
  scope :with_damage, -> { where("condition_data->>'exterior_damage' IS NOT NULL") }
  
  # ========================
  # INSTANCE METHODS
  # ========================
  
  # Check if report has been signed
  def signed?
    signature_data.present? && driver_name.present? && signed_at.present?
  end
  
  # Check if any exterior damage was reported
  def exterior_damage?
    exterior_damage.present? && exterior_damage != ['none'] && exterior_damage.exclude?('none')
  end
  
  # Get human-readable exterior damage summary
  def exterior_damage_summary
    return "No exterior damage noted" unless exterior_damage?
    
    damage_map = {
      'scratches' => 'Scratches',
      'dents' => 'Dents',
      'paint' => 'Paint damage',
      'glass' => 'Glass damage',
      'mirror' => 'Mirror damage',
      'lights' => 'Light damage'
    }
    
    damages = (exterior_damage || []).map { |d| damage_map[d] || d }.compact
    summary = damages.join(', ')
    
    if exterior_notes.present?
      summary += " (#{exterior_notes})"
    end
    
    summary
  end
  
  # Check if any interior issues were reported
  def interior_issues?
    interior_issues.present? && interior_issues != ['clean'] && interior_issues.exclude?('clean')
  end
  
  # Get human-readable interior summary
  def interior_summary
    return "Clean interior" unless interior_issues?
    
    issue_map = {
      'dirty' => 'Dirty',
      'seat_damage' => 'Seat damage',
      'carpet_damage' => 'Carpet damage',
      'dashboard_damage' => 'Dashboard damage',
      'odor' => 'Unusual odor'
    }
    
    (interior_issues || []).map { |i| issue_map[i] || i }.compact.join(', ')
  end
  
  # Get human-readable tire status
  def tire_status_display
    case tire_status
    when 'good'
      '✅ Good condition'
    when 'low_pressure'
      '⚠️ Low pressure'
    when 'damage'
      '🔴 Visible damage'
    else
      'Not specified'
    end
  end
  
  # Get human-readable warning lights
  def warning_lights_display
    return "No warning lights" if warning_lights.blank? || warning_lights.include?('none')
    
    light_map = {
      'check_engine' => 'Check Engine',
      'other' => 'Other lights'
    }
    
    (warning_lights || []).map { |l| light_map[l] || l }.compact.join(', ')
  end
  
  # Check if all required photos were taken
  def photos_complete?
    required_photos = ['front', 'rear', 'left', 'right', 'dashboard', 'odometer', 'fuel_gauge']
    taken = photos_taken || []
    (required_photos - taken).empty?
  end
  
  # Get list of missing photos
  def missing_photos
    required_photos = ['front', 'rear', 'left', 'right', 'dashboard', 'odometer', 'fuel_gauge']
    taken = photos_taken || []
    required_photos - taken
  end
  
  # Generate a PDF report for printing/signing
  def to_pdf
    # This would use Prawn or similar to generate a PDF
    # For now, just a placeholder
    {
      vehicle: vehicle.license_plate,
      driver: driver_name,
      signed_at: signed_at,
      exterior: exterior_damage_summary,
      interior: interior_summary,
      tires: tire_status_display,
      fuel: "#{fuel_level}%",
      odometer: "#{odometer} km"
    }
  end
  
  private
  
  def set_signed_at
    self.signed_at = Time.current if signature_data.present? && !signed_at.present?
  end
  
  def update_reception_log
    if reception_log.present?
      reception_log.update(
        condition_report_id: self.id,
        condition_status: exterior_damage? ? 'damage_noted' : 'clean'
      )
    end
  end
end