# app/models/account_transaction.rb
class AccountTransaction < ApplicationRecord
  belongs_to :debit_account, class_name: 'Account'
  belongs_to :credit_account, class_name: 'Account'
  belongs_to :payable, optional: true
  belongs_to :agency, optional: true
  belongs_to :reference, polymorphic: true, optional: true
  
  validates :transaction_number, presence: true, uniqueness: true
  validates :transaction_date, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validates :transaction_type, presence: true
  
  before_validation :generate_transaction_number, on: :create
  after_create :update_account_balances
  
  TRANSACTION_TYPES = {
    payment: 'payment',
    receipt: 'receipt',
    journal: 'journal',
    adjustment: 'adjustment',
    transfer: 'transfer'
  }.freeze
  
  def self.record_payment(payable:, amount:, payment_method:, reference_number:, payment_date: Date.current)
    transaction do
      # Find the payment account based on payment method
      payment_account = case payment_method
        when 'cash'
          Account.cash_accounts.for_agency(payable.agency_id).first
        when 'bank_transfer', 'cheque'
          Account.bank_accounts.for_agency(payable.agency_id).first
        when /card/
          Account.credit_card_accounts.for_agency(payable.agency_id).first
        else
          Account.bank_accounts.for_agency(payable.agency_id).first
      end
      
      # Debit accounts payable (reduce liability), credit payment account (reduce asset)
      create!(
        transaction_number: "PAY-#{reference_number}",
        transaction_date: payment_date,
        debit_account_id: payable.account_id,  # Debit accounts payable (reduce liability)
        credit_account_id: payment_account.id, # Credit payment account (reduce asset)
        amount: amount,
        transaction_type: 'payment',
        reference_type: 'Payable',
        reference_id: payable.id,
        payable_id: payable.id,
        agency_id: payable.agency_id,
        description: "Payment for #{payable.reference_number} via #{payment_method}",
        notes: "Reference: #{reference_number}"
      )
    end
  end
  
  private
  
  def generate_transaction_number
    return if transaction_number.present?
    
    date_prefix = transaction_date.strftime('%Y%m%d')
    last_trx = AccountTransaction.where('transaction_number LIKE ?', "TRX-#{date_prefix}-%").last
    
    if last_trx
      last_num = last_trx.transaction_number.split('-').last.to_i
      self.transaction_number = "TRX-#{date_prefix}-#{format('%04d', last_num + 1)}"
    else
      self.transaction_number = "TRX-#{date_prefix}-0001"
    end
  end
  
  def update_account_balances
    # Update debit account balance
    debit_account.debit(amount)
    
    # Update credit account balance
    credit_account.credit(amount)
  end
end