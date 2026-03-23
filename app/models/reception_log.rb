# app/models/reception_log.rb
# UPDATED: Renamed receptionist to security_gate_officer
# Added association with condition_report
# Added customer portal functionality

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
  
  # NEW: Email validation for customer portal
  validates :customer_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  
  # Callbacks
  after_create :create_vehicle_status
  before_validation :set_default_received_at, if: -> { received_at.blank? && check_in_time.present? }
  before_validation :set_default_driver_name, if: -> { driver_name.blank? && visitor_name.present? }
  
  # Scopes
  scope :today, -> { where(received_at: Date.current.all_day) }
  scope :pending_inspection, -> { where(inspected_at: nil) }
  scope :with_damage_noted, -> { where(condition_status: 'damage_noted') }  # <-- ADDED
  scope :clean_arrival, -> { where(condition_status: 'clean') }  # <-- ADDED
  scope :with_portal_access, -> { where.not(portal_access_token: nil).where('portal_access_expires_at > ?', Time.current) }
  scope :expired_portal_access, -> { where('portal_access_expires_at < ?', Time.current).where.not(portal_access_token: nil) }
  
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
  
  # ============================================
  # NEW: Customer Portal Methods
  # ============================================
  
  # Generate a unique receipt number for portal access
  def generate_receipt_number!
    return if receipt_number.present?
    new_receipt_number = "RCP-#{Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
    update_column(:receipt_number, new_receipt_number)
  end
  
  # Generate portal access token
  def generate_portal_access_token!
    update!(
      portal_access_token: SecureRandom.hex(32),
      portal_access_expires_at: 7.days.from_now
    )
  end
  
  # Check if portal access is still valid
  def portal_access_valid?
    portal_access_token.present? && portal_access_expires_at > Time.current
  end
  
  # Get the portal login URL
  def portal_login_url
    return nil unless portal_access_token.present?
    Rails.application.routes.url_helpers.customer_login_url(token: portal_access_token)
  end
  
  # Send portal invitation email
  def send_portal_invitation!
    return if customer_email.blank?
    
    generate_portal_access_token! unless portal_access_valid?
    generate_receipt_number! if receipt_number.blank?
    
    # Send email (create this mailer)
    # CustomerPortalMailer.invitation(self).deliver_later
    
    # Log that invitation was sent
    update_column(:portal_invitation_sent_at, Time.current)
  end
  
  # Get the inspection for this reception
  def inspection
    Inspection.find_by(vehicle_id: vehicle_id, created_at: created_at..(created_at + 1.hour))
  end
  
  # Get the latest quotation for this vehicle's inspection
  def latest_quotation
    inspection&.quotations&.last
  end
  
  # Get the work progress percentage
  def work_progress_percentage
    insp = inspection
    return 0 unless insp
    
    total_jobs = insp.inspection_jobs.count
    return 0 if total_jobs == 0
    
    completed_jobs = insp.inspection_jobs.where(completed_at: nil).count
    ((completed_jobs.to_f / total_jobs) * 100).round
  end
  
  # Get portal access status for display
  def portal_access_status
    if portal_access_token.blank?
      "Not Generated"
    elsif portal_access_expires_at < Time.current
      "Expired on #{portal_access_expires_at.strftime('%b %d, %Y')}"
    else
      "Active until #{portal_access_expires_at.strftime('%b %d, %Y')}"
    end
  end
  
  # Get portal access badge class
  def portal_access_badge_class
    if portal_access_token.blank?
      'bg-secondary'
    elsif portal_access_expires_at < Time.current
      'bg-danger'
    else
      'bg-success'
    end
  end
  
  # Get portal access link for display
  def portal_access_link
    return nil unless portal_access_token.present?
    "/customer/login?token=#{portal_access_token}"
  end

  private
  
  def set_default_received_at
    self.received_at = check_in_time
  end
  
  def set_default_driver_name
    self.driver_name = visitor_name
  end
end