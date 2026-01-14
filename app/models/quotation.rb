# app/models/quotation.rb
class Quotation < ApplicationRecord
  belongs_to :vehicle, optional: true
  belongs_to :created_by, class_name: 'User'
  
  enum :status, {
    draft: 0,
    sent: 1,
    accepted: 2,
    rejected: 3,
    expired: 4
  }, default: :draft
  
  validates :quote_number, presence: true, uniqueness: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :vendor, presence: true
  
  scope :pending, -> { where(status: [:draft, :sent]) }
  scope :active, -> { where('valid_to >= ?', Date.today).where(status: [:draft, :sent]) }
  scope :expired, -> { where('valid_to < ?', Date.today).or(where(status: :expired)) }
  
  before_validation :generate_quote_number, on: :create
  before_validation :set_default_dates, on: :create
  
  def generate_quote_number
    self.quote_number ||= "QTE-#{Time.now.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
  end
  
  def set_default_dates
    self.valid_from ||= Date.today
    self.valid_to ||= Date.today + 30.days
  end
  
  def accept!
    update(status: :accepted, accepted_at: Time.current)
  end
  
  def reject!(reason = nil)
    update(
      status: :rejected,
      notes: [notes, "Rejected on #{Date.today}: #{reason}"].compact.join("\n\n")
    )
  end
  
  def expire!
    update(status: :expired) if valid_to < Date.today && [:draft, :sent].include?(status.to_sym)
  end
  
  def days_until_expiry
    return nil unless valid_to
    (valid_to - Date.today).to_i
  end
  
  def expired?
    valid_to < Date.today || status.to_sym == :expired
  end
  
  def display_status
    status.humanize
  end
end