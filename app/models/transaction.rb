# app/models/transaction.rb
class Transaction < ApplicationRecord
  belongs_to :invoice, optional: true
  belongs_to :vehicle, optional: true
  belongs_to :user
  
  # Add this association
  has_one :payment_history, foreign_key: "payment_transaction_id", dependent: :nullify
  
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
  
  # Update this method to also create payment history
  def self.record_payment(params)
    transaction = nil
    
    ActiveRecord::Base.transaction do
      transaction = new(params)
      transaction.status = :completed
      transaction.transaction_type = :payment
      transaction.save!
      
      # Create payment history if invoice is provided
      if transaction.invoice_id
        PaymentHistory.create_from_transaction(transaction, transaction.invoice_id)
      end
    end
    
    transaction
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Failed to record payment: #{e.message}"
    nil
  end
  
  def display_status
    status.humanize
  end
  
  # Check if transaction has a payment history
  def has_payment_history?
    payment_history.present?
  end
  
  # Get agency through invoice -> vehicle
  def agency
    invoice&.vehicle&.agency
  end
end