# app/models/transaction.rb
class Transaction < ApplicationRecord
  belongs_to :invoice, optional: true
  belongs_to :vehicle, optional: true
  belongs_to :user
  
  enum :status, {
    pending: 0,
    completed: 1,
    failed: 2,
    voided: 3,
    refunded: 4
  }, default: :pending
  
  enum :transaction_type, {
    payment: 0,
    refund: 1,
    adjustment: 2,
    deposit: 3
  }, default: :payment
  
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :reference_number, uniqueness: true, allow_blank: true
  
  scope :completed, -> { where(status: :completed) }
  scope :this_month, -> { where(created_at: Time.current.beginning_of_month..Time.current.end_of_month) }
  scope :for_invoice, ->(invoice_id) { where(invoice_id: invoice_id) }
  
  before_create :generate_reference_number
  
  def generate_reference_number
    self.reference_number ||= "TXN-#{Time.now.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
  end
  
  def self.record_payment(params)
    transaction = new(params)
    transaction.status = :completed
    transaction.transaction_type = :payment
    transaction.save
    transaction
  end
  
  def display_status
    status.humanize
  end
end