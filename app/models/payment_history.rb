# app/models/payment_history.rb
class PaymentHistory < ApplicationRecord
  # ========================
  # Associations
  # ========================
  belongs_to :invoice
  belongs_to :user, optional: true  # User who recorded the payment
  
  # Optional: If you have payment transactions
  belongs_to :payment_transaction, polymorphic: true, optional: true

  # ========================
  # Validations
  # ========================
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :payment_date, presence: true
  validates :status, presence: true, inclusion: { in: %w[completed pending failed refunded] }
  validates :payment_method, presence: true
  validates :reference_number, uniqueness: true, allow_blank: true

  # ========================
  # Callbacks
  # ========================
  before_validation :set_defaults, on: :create
  after_create :update_invoice_payment_status
  after_update :update_invoice_payment_status, if: :saved_change_to_status?

  # ========================
  # Scopes
  # ========================
  scope :completed, -> { where(status: 'completed') }
  scope :pending, -> { where(status: 'pending') }
  scope :failed, -> { where(status: 'failed') }
  scope :refunded, -> { where(status: 'refunded') }
  scope :for_date, ->(date) { where(payment_date: date) }
  scope :for_date_range, ->(start_date, end_date) { where(payment_date: start_date..end_date) }
  scope :by_method, ->(method) { where(payment_method: method) }
  scope :by_user, ->(user_id) { where(user_id: user_id) }
  scope :recent, -> { order(created_at: :desc) }

  # ========================
  # Instance Methods
  # ========================
  
  def completed?
    status == 'completed'
  end

  def pending?
    status == 'pending'
  end

  def failed?
    status == 'failed'
  end

  def refunded?
    status == 'refunded'
  end

  def mark_as_completed!
    update(status: 'completed')
  end

  def mark_as_failed!
    update(status: 'failed')
  end

  def mark_as_refunded!
    update(status: 'refunded')
  end

  def payment_method_display
    case payment_method
    when 'bank_transfer'
      'Bank Transfer'
    when 'cheque'
      'Cheque'
    when 'cash'
      'Cash'
    when 'credit_card'
      'Credit Card'
    when 'debit_card'
      'Debit Card'
    when 'trinidad_debit_card'
      '🇹🇹 Debit Card'
    when 'trinidad_credit_card'
      '🇹🇹 Credit Card'
    else
      payment_method.to_s.humanize
    end
  end

  def status_badge_color
    case status
    when 'completed' then 'success'
    when 'pending' then 'warning'
    when 'failed' then 'danger'
    when 'refunded' then 'info'
    else 'secondary'
    end
  end

  def formatted_amount
    ActionController::Base.helpers.number_to_currency(amount)
  end

  def formatted_payment_date
    payment_date.strftime("%B %d, %Y")
  end

  def short_reference
    reference_number.to_s.split('-').last || reference_number
  end

  # ========================
  # Class Methods
  # ========================
  
  def self.total_payments_for_date_range(start_date, end_date)
    for_date_range(start_date, end_date).completed.sum(:amount)
  end

  def self.payments_by_method(start_date, end_date)
    for_date_range(start_date, end_date)
      .completed
      .group(:payment_method)
      .sum(:amount)
  end

  def self.daily_totals(start_date, end_date)
    for_date_range(start_date, end_date)
      .completed
      .group(:payment_date)
      .sum(:amount)
  end

  def self.generate_reference_number
    "PAY-#{Date.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
  end

  private

  def set_defaults
    self.status ||= 'pending'
    self.payment_date ||= Date.current
    self.reference_number ||= self.class.generate_reference_number
  end

  def update_invoice_payment_status
    return unless invoice
    return unless status == 'completed'
    
    # Check if all payments sum to invoice amount
    total_paid = invoice.payment_histories.completed.sum(:amount)
    
    if total_paid >= invoice.amount
      invoice.update(
        status: 'paid',
        paid_at: Time.current
      )
    elsif total_paid > 0
      invoice.update(status: 'partially_paid')
    end
  end
end