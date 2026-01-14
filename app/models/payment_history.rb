class PaymentHistory < ApplicationRecord
  belongs_to :invoice
  belongs_to :transaction
  
  # Add any validations or methods you need
  validates :payment_date, presence: true
  validates :amount, numericality: { greater_than: 0 }
end