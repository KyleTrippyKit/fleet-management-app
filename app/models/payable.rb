# app/models/payable.rb
class Payable < ApplicationRecord
  belongs_to :vendor, optional: true
  belongs_to :purchase_order, optional: true
  belongs_to :invoice, optional: true
  belongs_to :agency, optional: true
  belongs_to :account
  
  has_many :account_transactions, dependent: :restrict_with_error
  has_many :payment_histories, as: :payment_transaction, dependent: :destroy
  has_one :payment_schedule, dependent: :destroy
  
  validates :reference_number, presence: true, uniqueness: true
  validates :vendor_name, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validates :amount_due, numericality: { greater_than_or_equal_to: 0 }
  validates :due_date, presence: true
  
  enum :status, {
    draft: 'draft',
    open: 'open',
    partially_paid: 'partially_paid',
    paid: 'paid',
    overdue: 'overdue',
    cancelled: 'cancelled'
  }, default: 'open'
  
  before_validation :generate_reference_number, on: :create
  before_save :update_amount_due
  after_create :create_account_transaction
  after_update :update_status_if_paid
  
  scope :open, -> { where(status: 'open') }
  scope :overdue, -> { where('due_date < ? AND status IN (?)', Date.current, ['open', 'partially_paid']) }
  scope :due_this_month, -> { 
    where('due_date BETWEEN ? AND ? AND status IN (?)', 
          Date.current.beginning_of_month, 
          Date.current.end_of_month, 
          ['open', 'partially_paid']) 
  }
  scope :by_vendor, ->(vendor_id) { where(vendor_id: vendor_id) }
  scope :by_agency, ->(agency_id) { where(agency_id: agency_id) }
  
  def self.create_from_purchase_order(purchase_order)
    payable_account = Account.payable_accounts.for_agency(purchase_order.agency_id).first
    
    create!(
      purchase_order_id: purchase_order.id,
      vendor_name: purchase_order.vendor,
      agency_id: purchase_order.agency_id,
      amount: purchase_order.amount,
      amount_due: purchase_order.amount,
      due_date: calculate_due_date(purchase_order.created_at, 'net_30'),
      account_id: payable_account.id,
      description: "Purchase Order #{purchase_order.po_number}",
      category: 'purchase_order'
    )
  end
  
  def self.create_from_invoice(invoice)
    payable_account = Account.payable_accounts.for_agency(invoice.agency_id).first
    
    create!(
      invoice_id: invoice.id,
      vendor_name: invoice.vendor,
      agency_id: invoice.agency_id,
      amount: invoice.amount,
      amount_due: invoice.amount,
      due_date: invoice.due_date,
      account_id: payable_account.id,
      description: "Invoice #{invoice.invoice_number}",
      category: 'invoice'
    )
  end
  
  def record_payment(payment_amount, payment_method, reference_number, payment_date = Date.current)
    transaction do
      # Create payment transaction
      AccountTransaction.record_payment(
        payable: self,
        amount: payment_amount,
        payment_method: payment_method,
        reference_number: reference_number,
        payment_date: payment_date
      )
      
      # Update payable
      self.amount_due -= payment_amount
      
      if amount_due <= 0
        self.status = 'paid'
        self.paid_at = Time.current
      elsif amount_due < amount
        self.status = 'partially_paid'
      end
      
      save!
      
      # Create payment history
      payment_histories.create!(
        amount: payment_amount,
        payment_date: payment_date,
        payment_method: payment_method,
        reference_number: reference_number,
        status: 'completed',
        notes: "Payment for #{reference_number}"
      )
    end
  end
  
  def monthly_statement_line_item
    {
      payable_id: id,
      reference_number: reference_number,
      description: description,
      original_amount: amount,
      amount_due: amount_due,
      due_date: due_date,
      status: status
    }
  end
  
  private
  
  def generate_reference_number
    return if reference_number.present?
    
    date_prefix = Date.current.strftime('%Y%m%d')
    last_payable = Payable.where('reference_number LIKE ?', "PAY-#{date_prefix}-%").last
    
    if last_payable
      last_num = last_payable.reference_number.split('-').last.to_i
      self.reference_number = "PAY-#{date_prefix}-#{format('%03d', last_num + 1)}"
    else
      self.reference_number = "PAY-#{date_prefix}-001"
    end
  end
  
  def update_amount_due
    self.amount_due = amount if new_record?
  end
  
  def create_account_transaction
    # When payable is created, credit accounts payable, debit expense
    expense_account = Account.where(
      agency_id: agency_id,
      sub_type: 'vehicle_maintenance_expense'
    ).first_or_create(
      account_number: '5010',
      name: 'Vehicle Maintenance Expense',
      account_type: 'expense',
      sub_type: 'vehicle_maintenance_expense'
    )
    
    AccountTransaction.create!(
      transaction_number: "TRX-#{reference_number}",
      transaction_date: Date.current,
      debit_account_id: expense_account.id,  # Debit expense
      credit_account_id: account_id,         # Credit accounts payable
      amount: amount,
      transaction_type: 'journal',
      reference_type: 'Payable',
      reference_id: id,
      payable_id: id,
      agency_id: agency_id,
      description: "Accounts payable created: #{description}"
    )
  end
  
  def update_status_if_paid
    if saved_change_to_amount_due? && amount_due <= 0 && status != 'paid'
      update_column(:status, 'paid')
    end
  end
  
  def self.calculate_due_date(transaction_date, terms)
    case terms
    when 'net_30'
      transaction_date + 30.days
    when 'net_15'
      transaction_date + 15.days
    when 'net_45'
      transaction_date + 45.days
    when 'net_60'
      transaction_date + 60.days
    when 'due_on_receipt'
      transaction_date
    else
      transaction_date + 30.days
    end
  end
end