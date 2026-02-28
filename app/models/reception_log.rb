class ReceptionLog < ApplicationRecord
  # Associations
  belongs_to :vehicle
  belongs_to :receptionist, class_name: 'User', foreign_key: 'user_id'
  belongs_to :inspector, class_name: 'User', optional: true, foreign_key: 'inspector_id'
  belongs_to :purchase_order, optional: true
  
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
      created_by: receptionist
    )
  end
  
  private
  
  def set_default_received_at
    self.received_at = check_in_time
  end
  
  def set_default_driver_name
    self.driver_name = visitor_name
  end
end