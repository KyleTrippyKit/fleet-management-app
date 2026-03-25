# app/models/reception_log.rb
# UPDATED: Renamed receptionist to security_gate_officer
# Added association with condition_report
# Added enhanced customer portal functionality

class ReceptionLog < ApplicationRecord
  after_initialize :debug_attributes

  def debug_attributes
    puts "DEBUG: ReceptionLog attributes: #{attributes.inspect}"
  end
  # Associations
  belongs_to :vehicle
  belongs_to :security_gate_officer, class_name: 'User', foreign_key: 'user_id'
  belongs_to :inspector, class_name: 'User', optional: true, foreign_key: 'inspector_id'
  belongs_to :purchase_order, optional: true
  belongs_to :condition_report, class_name: 'VehicleConditionReport', optional: true
  
  # Validations
  validates :vehicle_id, presence: true
  validates :user_id, presence: true
  validates :driver_name, presence: true
  validates :customer_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  
  # Callbacks
  after_create :create_vehicle_status
  before_create :generate_receipt_number, if: -> { receipt_number.blank? }
  before_validation :set_default_received_at, if: -> { received_at.blank? && check_in_time.present? }
  before_validation :set_default_driver_name, if: -> { driver_name.blank? && visitor_name.present? }
  
  # Scopes
  scope :today, -> { where(received_at: Date.current.all_day) }
  scope :pending_inspection, -> { where(inspected_at: nil) }
  scope :with_damage_noted, -> { where(condition_status: 'damage_noted') }
  scope :clean_arrival, -> { where(condition_status: 'clean') }
  scope :with_portal_access, -> { where.not(portal_access_token: nil).where('portal_access_expires_at > ?', Time.current) }
  scope :expired_portal_access, -> { where('portal_access_expires_at < ?', Time.current).where.not(portal_access_token: nil) }
  
  # Attributes
  attribute :condition_status, :string, default: 'pending'
  
  # Existing Methods
  def inspected?
    inspected_at.present?
  end
  
  def time_since_received
    return unless received_at
    ((Time.current - received_at) / 1.hour).round(1)
  end
  
  def create_vehicle_status
    puts "DEBUG: Creating VehicleStatus with user_id: #{user_id}"
    VehicleStatus.create!(
      vehicle: vehicle,
      status: 'vehicle_received',
      notes: "Received from #{driver_name} at #{received_at.strftime('%I:%M %p')}",
      current: true,
      created_by_id: user_id
    )
  end
  
  def link_condition_report(report)
    update(
      condition_report: report,
      condition_status: report.exterior_damage? ? 'damage_noted' : 'clean'
    )
  end
  
  def damage_noted?
    condition_status == 'damage_noted'
  end
  
  def condition_summary
    return "No condition report" unless condition_report
    
    if damage_noted?
      "Damage noted: #{condition_report.exterior_damage_summary}"
    else
      "Vehicle arrived in good condition"
    end
  end
  
  def condition_badge_class
    case condition_status
    when 'clean' then 'bg-success'
    when 'damage_noted' then 'bg-warning'
    when 'disputed' then 'bg-danger'
    else 'bg-secondary'
    end
  end
  
  def condition_display
    case condition_status
    when 'clean' then '✅ Clean arrival'
    when 'damage_noted' then '⚠️ Damage noted'
    when 'disputed' then '🔴 Disputed'
    else 'Pending'
    end
  end
  
  # ============================================
  # ENHANCED CUSTOMER PORTAL METHODS
  # ============================================
  
  # Generate a unique receipt number for portal access
  def generate_receipt_number
    return if receipt_number.present?
    self.receipt_number = "RCP-#{Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
  end
  
  def generate_receipt_number!
    generate_receipt_number
    save! if changed?
  end
  
  # Generate portal access token (30 days expiry)
  def generate_portal_access_token!
    update!(
      portal_access_token: SecureRandom.hex(32),
      portal_access_expires_at: 30.days.from_now,
      portal_invitation_sent_at: Time.current
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
    
    CustomerPortalMailer.invitation(self).deliver_later if defined?(CustomerPortalMailer)
    update_column(:portal_invitation_sent_at, Time.current)
  end
  
  # Send recovery email with login details
  def send_recovery_email!
    return if customer_email.blank?
    
    generate_portal_access_token! if !portal_access_valid? || portal_access_token.blank?
    generate_receipt_number! if receipt_number.blank?
    
    CustomerPortalMailer.recovery(self).deliver_later if defined?(CustomerPortalMailer)
    update_column(:recovery_email_sent_at, Time.current)
  end
  
  # Get full customer name
  def customer_full_name
    customer_name.presence || driver_name.presence || visitor_name.presence || "Valued Customer"
  end
  
  # Get customer display info for portal
  def customer_display_info
    {
      name: customer_full_name,
      email: customer_email,
      phone: customer_phone,
      receipt_number: receipt_number,
      license_plate: vehicle&.license_plate,
      vehicle_make: vehicle&.make,
      vehicle_model: vehicle&.model,
      dropoff_date: created_at,
      portal_active: portal_access_valid?,
      portal_expires_at: portal_access_expires_at
    }
  end
  
  # Get the inspection for this reception
  def inspection
    Inspection.find_by(vehicle_id: vehicle_id, created_at: created_at..(created_at + 1.hour))
  end
  
  # Get the latest quotation
  def latest_quotation
    inspection&.quotations&.last
  end
  
  # Get work progress percentage
  def work_progress_percentage
    insp = inspection
    return 0 unless insp
    
    total_jobs = insp.inspection_jobs.count
    return 0 if total_jobs == 0
    
    completed_jobs = insp.inspection_jobs.where.not(completed_at: nil).count
    ((completed_jobs.to_f / total_jobs) * 100).round
  end
  
  # Portal status for display
  def portal_access_status
    if portal_access_token.blank?
      "Not Generated"
    elsif portal_access_expires_at < Time.current
      "Expired on #{portal_access_expires_at.strftime('%b %d, %Y')}"
    else
      "Active until #{portal_access_expires_at.strftime('%b %d, %Y')}"
    end
  end
  
  def portal_access_badge_class
    if portal_access_token.blank?
      'bg-secondary'
    elsif portal_access_expires_at < Time.current
      'bg-danger'
    else
      'bg-success'
    end
  end
  
  # Generate a summary for customer service
  def customer_service_summary
    {
      id: id,
      receipt_number: receipt_number,
      customer_name: customer_full_name,
      customer_email: customer_email,
      customer_phone: customer_phone,
      vehicle: "#{vehicle&.make} #{vehicle&.model} (#{vehicle&.license_plate})",
      dropoff_date: created_at.strftime("%B %d, %Y at %I:%M %p"),
      status: inspection&.status || 'Pending',
      portal_active: portal_access_valid?,
      portal_token: portal_access_token,
      created_by_id: user_id
    }
  end

  private
  
  def set_default_received_at
    self.received_at = check_in_time
  end
  
  def set_default_driver_name
    self.driver_name = visitor_name
  end
end