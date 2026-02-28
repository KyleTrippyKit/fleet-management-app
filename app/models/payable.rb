# app/models/payable.rb
class Payable < ApplicationRecord
  # -------------------------
  # Associations
  # -------------------------
  belongs_to :vendor, class_name: 'Supplier', foreign_key: 'vendor_id', optional: true
  belongs_to :purchase_order, optional: true
  belongs_to :invoice, optional: true
  belongs_to :agency, optional: true
  belongs_to :account

  has_many :account_transactions, dependent: :restrict_with_error
  has_many :payment_histories, as: :payment_transaction, dependent: :destroy
  # has_one :payment_schedule, dependent: :destroy  # COMMENTED OUT

  # -------------------------
  # Validations
  # -------------------------
  validates :reference_number, presence: true, uniqueness: true
  validates :vendor_name, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validates :amount_due, numericality: { greater_than_or_equal_to: 0 }
  validates :due_date, presence: true
  validates :account, presence: true

  # -------------------------
  # Enums
  # -------------------------
  enum :status, {
    draft: 'draft',
    open: 'open',
    partially_paid: 'partially_paid',
    paid: 'paid',
    overdue: 'overdue',
    cancelled: 'cancelled'
  }, default: 'open'

  # -------------------------
  # Callbacks
  # -------------------------
  before_validation :generate_reference_number, on: :create
  before_validation :default_amount_due, on: :create

  after_create :create_account_transaction
  after_update :update_status_if_paid

  # -------------------------
  # Scopes - FIXED with fully qualified column names
  # -------------------------
  scope :open, -> { where(status: 'open') }
  
  # FIXED: Use table_name to avoid ambiguous column errors
  scope :overdue, -> { 
    where("#{table_name}.due_date < ? AND #{table_name}.status IN (?)", 
          Date.current, %w[open partially_paid]) 
  }
  
  scope :due_this_month, -> {
    where("#{table_name}.due_date BETWEEN ? AND ? AND #{table_name}.status IN (?)",
      Date.current.beginning_of_month,
      Date.current.end_of_month,
      %w[open partially_paid]
    )
  }
  
  scope :by_vendor, ->(vendor_id) { where(vendor_id: vendor_id) }
  scope :by_agency, ->(agency_id) { where(agency_id: agency_id) }

  # -------------------------
  # Factories
  # -------------------------
  def self.create_from_purchase_order(purchase_order)
    payable_account = Account.payable_accounts.for_agency(purchase_order.agency_id).first
    raise "No AP account found for agency_id=#{purchase_order.agency_id}" if payable_account.nil?

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
    raise "No AP account found for agency_id=#{invoice.agency_id}" if payable_account.nil?

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

  # -------------------------
  # Instance Methods
  # -------------------------
  
  def vendor_info
    return nil unless vendor_id.present?
    Supplier.find_by(id: vendor_id)
  end

  def vendor_name_with_details
    if vendor.present?
      "#{vendor_name} (#{vendor.contact_person})"
    else
      vendor_name
    end
  end

  # -------------------------
  # Payments
  # -------------------------
  def record_payment(payment_amount, payment_method, reference_number, payment_date = Date.current)
    transaction do
      AccountTransaction.record_payment(
        payable: self,
        amount: payment_amount,
        payment_method: payment_method,
        reference_number: reference_number,
        payment_date: payment_date
      )

      self.amount_due -= payment_amount

      if amount_due <= 0
        self.status = 'paid'
        self.paid_at = Time.current
      elsif amount_due < amount
        self.status = 'partially_paid'
      end

      save!

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

  # -------------------------
  # Status Helpers
  # -------------------------
  def overdue?
    due_date < Date.current && ['open', 'partially_paid'].include?(status)
  end

  def paid_in_full?
    amount_due <= 0.01
  end

  def status_badge_color
    case status
    when 'paid' then 'success'
    when 'open' then 'warning'
    when 'overdue' then 'danger'
    when 'partially_paid' then 'info'
    when 'cancelled' then 'secondary'
    else 'dark'
    end
  end

  def status_display
    status.humanize
  end

  def days_overdue
    return 0 unless overdue?
    (Date.current - due_date).to_i
  end

  # -------------------------
  # Payment Progress
  # -------------------------
  def payment_percentage
    return 0 if amount.zero?
    ((amount - amount_due) / amount * 100).round
  end

  def paid_amount
    amount - amount_due
  end

  # -------------------------
  # Private
  # -------------------------
  private

  def generate_reference_number
    return if reference_number.present?

    date_prefix = Date.current.strftime('%Y%m%d')
    last_payable = Payable.where('reference_number LIKE ?', "PAY-#{date_prefix}-%").order(:id).last

    if last_payable
      last_num = last_payable.reference_number.split('-').last.to_i
      self.reference_number = "PAY-#{date_prefix}-#{format('%03d', last_num + 1)}"
    else
      self.reference_number = "PAY-#{date_prefix}-001"
    end
  end

  def default_amount_due
    self.amount_due = amount if amount_due.nil?
  end

  def create_account_transaction
    raise "Payable #{id} missing agency_id" if agency_id.blank?

    expense_account = Account.where(
      agency_id: agency_id,
      sub_type: 'utilities_expense'
    ).first_or_create!(
      account_number: '5010',
      name: 'Vehicle Maintenance Expense',
      account_type: 'expense',
      sub_type: 'utilities_expense'
    )

    AccountTransaction.create!(
      transaction_number: "TRX-#{reference_number}",
      transaction_date: Date.current,
      debit_account_id: expense_account.id,
      credit_account_id: account_id,
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
    return unless saved_change_to_amount_due?

    if amount_due.to_f <= 0 && status != 'paid'
      update_column(:status, 'paid')
    end
  end

  def self.calculate_due_date(transaction_date, terms)
    case terms
    when 'net_30' then transaction_date + 30.days
    when 'net_15' then transaction_date + 15.days
    when 'net_45' then transaction_date + 45.days
    when 'net_60' then transaction_date + 60.days
    when 'due_on_receipt' then transaction_date
    else transaction_date + 30.days
    end
  end
end