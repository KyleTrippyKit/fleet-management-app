# app/models/payment_history.rb
class PaymentHistory < ApplicationRecord
  belongs_to :invoice
  belongs_to :payment_transaction, class_name: "Transaction", foreign_key: "payment_transaction_id"
  
  # Delegate to get agency information through invoice -> vehicle
  delegate :agency, to: :invoice, allow_nil: true
  delegate :vehicle, to: :invoice, allow_nil: true
  delegate :vendor, to: :invoice, allow_nil: true
  
  # Validations
  validates :payment_date, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validates :payment_transaction_id, uniqueness: true
  
  # Status enum
  enum :status, {
    pending: 'pending',
    completed: 'completed',
    failed: 'failed',
    refunded: 'refunded'
  }, default: :completed
  
  # Agency isolation scopes
  scope :for_agency, ->(agency) { 
    joins(invoice: :vehicle).where(vehicles: { agency_id: agency.id }) 
  }
  
  scope :for_current_agency, -> {
    if User.current && User.current.agency_id
      for_agency(User.current.agency)
    else
      none
    end
  }
  
  # Default scope for agency isolation
  default_scope -> { 
    if User.current && User.current.agency_id
      joins(invoice: :vehicle).where(vehicles: { agency_id: User.current.agency_id })
    end
  }
  
  # Class method to bypass scoping for admin users
  def self.unscoped_for_admin
    if User.current&.is_admin?
      unscoped
    else
      all
    end
  end
  
  # Helper methods
  def agency_name
    agency&.name || "Unknown Agency"
  end
  
  def vehicle_registration
    vehicle&.registration_number || "Unknown Vehicle"
  end
  
  def invoice_number
    invoice&.invoice_number || "N/A"
  end
  
  # Transaction details
  def transaction_reference
    payment_transaction&.reference_number
  end
  
  def transaction_status
    payment_transaction&.display_status
  end
  
  # Payment summary
  def payment_summary
    "#{payment_method} payment of #{amount} on #{payment_date.strftime('%B %d, %Y')}"
  end
  
  # Create payment history from transaction
  def self.create_from_transaction(transaction, invoice_id, payment_date = Date.current)
    return unless transaction.completed?
    
    create!(
      invoice_id: invoice_id,
      payment_transaction_id: transaction.id,
      payment_date: payment_date,
      amount: transaction.amount,
      payment_method: transaction.payment_method || 'Unknown',
      reference_number: transaction.reference_number,
      status: :completed
    )
  end
end