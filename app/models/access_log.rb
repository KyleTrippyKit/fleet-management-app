# app/models/access_log.rb
class AccessLog < ApplicationRecord
  belongs_to :user
  belongs_to :agency, optional: true
  belongs_to :resource, polymorphic: true, optional: true
  belongs_to :approved_by, class_name: 'User', optional: true
  
  validates :action, presence: true
  
  # Set accessed_at before creation if not set
  before_create :set_accessed_at
  
  # Scopes
  scope :recent, -> { order(accessed_at: :desc).limit(100) }
  scope :by_user, ->(user) { where(user: user) }
  scope :by_agency, ->(agency) { where(agency: agency) }
  scope :sensitive_actions, -> { 
    where(action: ['tracking.live', 'tracking.history', 'users.manage', 'audit.view']) 
  }
  scope :today, -> { where(accessed_at: Time.current.all_day) }
  scope :gps_access, -> { where(access_type: ['gps_live', 'gps_history']) }
  scope :pending_approval, -> { where(approved: false).where.not(access_type: nil) }
  scope :approved, -> { where(approved: true) }
  
  # Trinidad compliance: Keep logs for 7 years
  def self.cleanup_old_logs
    where("accessed_at < ?", 7.years.ago).delete_all
  end
  
  # Helper to create a log entry from user
  def self.log_access(user, action, resource = nil, outcome: "granted", details: {}, access_type: nil)
    create(
      user: user,
      agency: user.primary_agency,
      action: action.to_s,
      resource: resource,
      accessed_at: Time.current,
      outcome: outcome,
      details: details,
      ip_address: Current.request&.remote_ip,
      user_agent: Current.request&.user_agent,
      access_type: access_type,
      approved: access_type.present? ? false : true  # GPS access requires approval
    )
  end
  
  def to_s
    "#{display_action} by #{user.email} at #{accessed_at&.strftime('%Y-%m-%d %H:%M') || 'N/A'}"
  end
  
  def display_action
    action.split('.').map(&:titleize).join(' ')
  end
  
  def approve!(approved_by_user, notes = nil)
    update!(
      approved: true,
      approved_at: Time.current,
      approved_by: approved_by_user,
      approval_notes: notes
    )
  end
  
  def requires_approval?
    access_type.present? && !approved?
  end
  
  private
  
  def set_accessed_at
    self.accessed_at ||= Time.current
  end
end