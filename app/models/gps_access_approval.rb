class GpsAccessApproval < ApplicationRecord
  belongs_to :user
  belongs_to :vehicle
  belongs_to :approver, class_name: 'User', optional: true
  
  validates :access_type, inclusion: { in: %w[live history replay] }
  validates :status, inclusion: { in: %w[pending approved denied expired] }
  
  scope :active, -> { where(status: 'approved').where('expires_at > ?', Time.current) }
  scope :pending, -> { where(status: 'pending') }
  scope :expired, -> { where('expires_at < ?', Time.current).or(where(status: 'expired')) }
  
  before_create :set_default_expiry
  
  def approve!(approver_user)
    update(
      approver: approver_user,
      approved_at: Time.current,
      expires_at: 24.hours.from_now,  # Default 24-hour approval
      status: 'approved'
    )
  end
  
  def deny!(approver_user)
    update(
      approver: approver_user,
      approved_at: Time.current,
      status: 'denied'
    )
  end
  
  def expired?
    expires_at.present? && expires_at < Time.current
  end
  
  def active?
    status == 'approved' && !expired?
  end
  
  private
  
  def set_default_expiry
    self.expires_at ||= 24.hours.from_now if status == 'approved'
  end
end