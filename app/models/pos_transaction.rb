# app/models/pos_transaction.rb
class PosTransaction < ApplicationRecord
  belongs_to :invoice, optional: true
  belongs_to :vehicle, optional: true
  belongs_to :user
  
  enum :status, {
    pending: 0,
    completed: 1,
    voided: 2,
    refunded: 3
  }, default: :pending
  
  enum :payment_type, {
    cash: 0,
    card: 1,
    mobile_money: 2,
    bank_transfer: 3
  }, default: :cash
  
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :transaction_id, presence: true, uniqueness: true
  
  scope :completed, -> { where(status: :completed) }
  scope :today, -> { where(created_at: Time.current.beginning_of_day..Time.current.end_of_day) }
  scope :this_month, -> { where(created_at: Time.current.beginning_of_month..Time.current.end_of_month) }
  
  before_validation :generate_transaction_id, on: :create
  
  def generate_transaction_id
    self.transaction_id ||= "POS-#{Time.now.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(4).upcase}"
  end
  
  def void!(reason = nil)
    update(
      status: :voided,
      voided_at: Time.current,
      notes: [notes, "Voided on #{Date.today}: #{reason}"].compact.join("\n\n")
    )
  end
  
  def refund!(reason = nil)
    update(
      status: :refunded,
      refunded_at: Time.current,
      notes: [notes, "Refunded on #{Date.today}: #{reason}"].compact.join("\n\n")
    )
  end
  
  def self.process_payment(params)
    transaction = new(params)
    transaction.status = :completed
    transaction.save
    transaction
  end
  
  def display_status
    status.humanize
  end
  
  def display_payment_type
    payment_type.humanize
  end
end