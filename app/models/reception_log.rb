# app/models/reception_log.rb
# UPDATED: Renamed receptionist to security_gate_officer
# Added association with condition_report

class ReceptionLog < ApplicationRecord
  # Associations
  belongs_to :vehicle
  belongs_to :security_gate_officer, class_name: 'User', foreign_key: 'user_id'  # <-- RENAMED
  belongs_to :inspector, class_name: 'User', optional: true, foreign_key: 'inspector_id'  # <-- KEPT AS inspector
  belongs_to :purchase_order, optional: true
  
  # NEW: Association with condition report from gate check-in
  belongs_to :condition_report, class_name: 'VehicleConditionReport', optional: true  # <-- ADDED
  
  # Validations
  validates :vehicle_id, presence: true
  validates :user_id, presence: true
  validates :driver_name, presence: true
  
  # Callbacks
  after_create :create_vehicle_status
  before_validation :set_default_received_at, if: -> { received_at.blank? && check_in_time.present? }
  before_validation :set_default_driver_name, if: -> { driver_name.blank? && visitor_name.present? }
  
  # Scopes
  scope :today, -> { where(received_at: Date.current.all_day) }
  scope :pending_inspection, -> { where(inspected_at: nil) }
  scope :with_damage_noted, -> { where(condition_status: 'damage_noted') }  # <-- ADDED
  scope :clean_arrival, -> { where(condition_status: 'clean') }  # <-- ADDED
  
  # Attributes for condition tracking
  attribute :condition_status, :string, default: 'pending'  # <-- ADDED: 'pending', 'clean', 'damage_noted', 'disputed'
  
  # Methods
  def inspected?
    inspected_at.present?
  end
  
  def time_since_received
    return unless received_at
    ((Time.current - received_at) / 1.hour).round(1)
  end
  
  def create_vehicle_status
    VehicleStatus.create!(
      vehicle: vehicle,
      status: 'vehicle_received',
      notes: "Received from #{driver_name} at #{received_at.strftime('%I:%M %p')}",
      current: true,
      created_by: security_gate_officer  # <-- UPDATED
    )
  end
  
  # NEW: Link to condition report
  def link_condition_report(report)
    update(
      condition_report: report,
      condition_status: report.exterior_damage? ? 'damage_noted' : 'clean'
    )
  end
  
  # NEW: Check if damage was noted
  def damage_noted?
    condition_status == 'damage_noted'
  end
  
  # NEW: Get condition summary
  def condition_summary
    return "No condition report" unless condition_report
    
    if damage_noted?
      "Damage noted: #{condition_report.exterior_damage_summary}"
    else
      "Vehicle arrived in good condition"
    end
  end
  
  # NEW: Get condition badge class for UI
  def condition_badge_class
    case condition_status
    when 'clean' then 'bg-success'
    when 'damage_noted' then 'bg-warning'
    when 'disputed' then 'bg-danger'
    else 'bg-secondary'
    end
  end
  
  # NEW: Get condition display text
  def condition_display
    case condition_status
    when 'clean' then '✅ Clean arrival'
    when 'damage_noted' then '⚠️ Damage noted'
    when 'disputed' then '🔴 Disputed'
    else 'Pending'
    end
  end
  
  private
  
  def set_default_received_at
    self.received_at = check_in_time
  end
  
  def set_default_driver_name
    self.driver_name = visitor_name
  end
end