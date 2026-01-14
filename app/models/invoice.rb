# app/models/invoice.rb
class Invoice < ApplicationRecord
  # Associations
  belongs_to :vehicle, optional: true
  belongs_to :maintenance, optional: true
  belongs_to :purchase_order, optional: true
  belongs_to :pos_transaction, optional: true
  
  # User references
  belongs_to :created_by, class_name: 'User', optional: true, foreign_key: :created_by_id
  belongs_to :received_by, class_name: 'User', optional: true, foreign_key: :received_by_id
  belongs_to :reviewed_by, class_name: 'User', optional: true, foreign_key: :reviewed_by_id
  belongs_to :paid_by, class_name: 'User', optional: true, foreign_key: :paid_by_id
  belongs_to :disputed_by, class_name: 'User', optional: true, foreign_key: :disputed_by_id
  
  # Payment and transaction associations
  has_many :transactions, dependent: :restrict_with_error
  has_many :payment_histories, dependent: :restrict_with_error
  
  # Agency delegation through vehicle
  delegate :agency, to: :vehicle, allow_nil: true
  delegate :agency_id, to: :vehicle, allow_nil: true
  
  # Quotations through vehicle
  has_many :quotations, through: :vehicle
  
  # Validations
  validates :invoice_number, presence: true, uniqueness: true
  validates :vendor, presence: true
  validates :invoice_date, :due_date, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  
  # Enums
  enum :status, {
    draft: 'draft',
    pending: 'pending',
    paid: 'paid', 
    overdue: 'overdue',
    disputed: 'disputed',
    cancelled: 'cancelled'
  }, default: 'pending'
  
  enum :category, {
    maintenance: 'maintenance',
    repair: 'repair',
    parts: 'parts',
    fuel: 'fuel',
    insurance: 'insurance',
    other: 'other'
  }, default: 'maintenance'
  
  # Scopes
  scope :overdue, -> { where('due_date < ? AND status = ?', Date.today, 'pending') }
  scope :pending, -> { where(status: 'pending') }
  scope :paid, -> { where(status: 'paid') }
  scope :disputed, -> { where(status: 'disputed') }
  scope :this_month, -> { where(invoice_date: Time.current.beginning_of_month..Time.current.end_of_month) }
  
  # Agency isolation scopes (NO User.current - use in controllers with current_user.agency)
  scope :for_agency, ->(agency) { 
    joins(:vehicle).where(vehicles: { agency_id: agency.id }) 
  }
  
  scope :by_service_owner, ->(service_owner) {
    joins(:vehicle).where(vehicles: { service_owner: service_owner })
  }
  
  # Integration scopes
  scope :with_quickbooks, -> { where.not(quickbooks_id: nil) }
  scope :without_quickbooks, -> { where(quickbooks_id: nil) }
  scope :with_purchase_order, -> { where.not(purchase_order_id: nil) }
  scope :with_pos_payment, -> { where.not(pos_transaction_id: nil) }
  scope :has_transactions, -> { joins(:transactions).distinct }
  
  # Review scopes
  scope :reviewed, -> { where.not(reviewed_by_id: nil) }
  scope :unreviewed, -> { where(reviewed_by_id: nil) }
  
  # Payment scopes
  scope :fully_paid, -> { where(status: 'paid') }
  scope :partially_paid, -> { 
    joins(:payment_histories)
      .where.not(status: 'paid')
      .group('invoices.id')
      .having('SUM(payment_histories.amount) > 0')
  }
  scope :unpaid, -> { pending.where.not(id: PaymentHistory.select(:invoice_id)) }
  
  # Search
  def self.search(query)
    return all if query.blank?
    
    where(
      "invoice_number ILIKE :q OR vendor ILIKE :q OR category ILIKE :q",
      q: "%#{query}%"
    )
  end
  
  # Status badge helper for views
  def status_badge_class
    case status
    when 'paid'
      'bg-success'
    when 'pending'
      if overdue?
        'bg-danger'
      else
        'bg-warning text-dark'
      end
    when 'overdue'
      'bg-danger'
    when 'disputed'
      'bg-warning'
    when 'cancelled'
      'bg-secondary'
    when 'draft'
      'bg-light text-dark'
    else
      'bg-info'
    end
  end
  
  # Get service owner from vehicle
  def service_owner
    vehicle&.service_owner
  end
  
  # Get agency name (alias for service_owner)
  def agency_name
    agency&.name || service_owner || 'Unknown Agency'
  end
  
  # Days until due (negative if overdue)
  def days_until_due
    return nil unless due_date
    (due_date - Date.today).to_i
  end
  
  # Check if invoice is overdue
  def overdue?
    pending? && due_date.present? && due_date < Date.today
  end
  
  # Get vehicle display info
  def vehicle_display
    return 'No vehicle assigned' unless vehicle
    "#{vehicle.license_plate} - #{vehicle.make} #{vehicle.model}"
  end
  
  # Calculate aging (days since invoice date)
  def aging_days
    return nil unless invoice_date
    (Date.today - invoice_date).to_i
  end
  
  # Payment calculations with PaymentHistory
  def total_payments_received
    payment_histories.completed.sum(:amount)
  end
  
  def balance_due
    amount - total_payments_received
  end
  
  def paid_in_full?
    balance_due <= 0
  end
  
  def payment_status
    if paid_in_full?
      'Paid in Full'
    elsif total_payments_received > 0
      'Partially Paid'
    else
      'Unpaid'
    end
  end
  
  # Legacy method for backward compatibility
  def total_paid
    total_payments_received + (pos_transaction&.amount || 0)
  end
  
  # Payment percentage
  def payment_percentage
    return 0 if amount.zero?
    ((total_payments_received / amount) * 100).round(2)
  end
  
  # Integration methods
  def quickbooks_synced?
    quickbooks_id.present?
  end
  
  def pos_payment_made?
    pos_transaction_id.present?
  end
  
  def has_purchase_order?
    purchase_order_id.present?
  end
  
  def has_transactions?
    transactions.any?
  end
  
  def has_payment_history?
    payment_histories.any?
  end
  
  def integration_badges
    badges = []
    badges << { label: 'QB', color: 'success', icon: 'check-circle', tooltip: 'Synced with QuickBooks' } if quickbooks_synced?
    badges << { label: 'POS', color: 'primary', icon: 'cash-coin', tooltip: 'POS Payment Made' } if pos_payment_made?
    badges << { label: 'PO', color: 'secondary', icon: 'cart-check', tooltip: 'Linked to Purchase Order' } if has_purchase_order?
    badges << { label: 'PAY', color: 'info', icon: 'credit-card', tooltip: 'Has Transactions' } if has_transactions?
    badges << { label: 'HIST', color: 'dark', icon: 'clock-history', tooltip: 'Has Payment History' } if has_payment_history?
    badges
  end
  
  # Mark methods
  def mark_as_paid(user = nil)
    update!(
      status: 'paid', 
      paid_by: user, 
      paid_at: Time.current
    )
  end
  
  def mark_as_reviewed(user = nil)
    update!(
      reviewed_by: user, 
      reviewed_at: Time.current
    )
  end
  
  def mark_as_disputed(reason = nil, user = nil)
    update!(
      status: 'disputed',
      disputed_by: user,
      disputed_at: Time.current,
      dispute_reason: reason,
      notes: [notes, "Disputed on #{Date.today} by #{user&.email || 'System'}: #{reason}"].compact.join("\n\n")
    )
  end
  
  # Check if invoice has been reviewed
  def reviewed?
    reviewed_by.present? || received_by.present?  # Support both for backward compatibility
  end
  
  # Get the user who reviewed the invoice
  def reviewer
    reviewed_by || received_by
  end
  
  # Get review timestamp
  def reviewed_at
    self[:reviewed_at] || received_at
  end
  
  # Payment History methods
  def payment_timeline
    timeline = []
    
    # Add payment history entries
    payment_histories.order(payment_date: :desc).each do |payment|
      timeline << {
        type: 'payment',
        date: payment.payment_date,
        amount: payment.amount,
        method: payment.payment_method,
        reference: payment.reference_number,
        notes: payment.notes,
        status: payment.status
      }
    end
    
    # Add transaction entries (for backward compatibility)
    transactions.completed.order(:created_at).each do |transaction|
      timeline << {
        type: 'transaction',
        date: transaction.created_at.to_date,
        amount: transaction.amount,
        method: transaction.payment_method,
        reference: transaction.reference_number,
        notes: transaction.notes,
        status: transaction.status
      }
    end
    
    timeline.sort_by { |entry| entry[:date] }.reverse
  end
  
  def recent_payments(count = 5)
    payment_histories.order(payment_date: :desc).limit(count)
  end
  
  # QuickBooks sync
  def sync_to_quickbooks
    return { success: true, message: 'Already synced' } if quickbooks_id.present?
    
    begin
      result = QuickbooksIntegration.sync_invoice(self)
      
      if result[:success]
        update!(
          quickbooks_id: result[:quickbooks_id], 
          last_sync_at: Time.current,
          sync_status: 'success'
        )
        { success: true, message: 'Synced successfully', quickbooks_id: result[:quickbooks_id] }
      else
        update!(sync_status: 'failed', sync_error: result[:error])
        { success: false, error: result[:error] }
      end
    rescue => e
      update!(sync_status: 'error', sync_error: e.message)
      { success: false, error: "QuickBooks sync error: #{e.message}" }
    end
  end
  
  # Generate invoice PDF
  def to_pdf
    # Enhanced text version with payment history
    content = "=" * 60 + "\n"
    content += "INVOICE\n"
    content += "=" * 60 + "\n\n"
    
    content += "Invoice Details:\n"
    content += "  Invoice #: #{invoice_number}\n"
    content += "  Date: #{invoice_date}\n"
    content += "  Due Date: #{due_date}\n"
    content += "  Status: #{status.upcase}\n"
    content += "  Category: #{category.titleize}\n\n"
    
    content += "Vendor Information:\n"
    content += "  Vendor: #{vendor}\n"
    content += "  Agency: #{agency_name}\n\n"
    
    content += "Vehicle Information:\n"
    content += "  Vehicle: #{vehicle_display}\n\n"
    
    content += "Financial Information:\n"
    content += "  Total Amount: $#{'%.2f' % amount}\n"
    content += "  Amount Paid: $#{'%.2f' % total_payments_received}\n"
    content += "  Balance Due: $#{'%.2f' % balance_due}\n"
    content += "  Payment Status: #{payment_status}\n"
    content += "  Payment Progress: #{payment_percentage}%\n\n"
    
    # Payment History Section
    if payment_histories.any?
      content += "Payment History:\n"
      content += "-" * 60 + "\n"
      payment_histories.order(payment_date: :desc).each_with_index do |payment, index|
        content += "#{index + 1}. Date: #{payment.payment_date}\n"
        content += "    Amount: $#{'%.2f' % payment.amount}\n"
        content += "    Method: #{payment.payment_method}\n"
        content += "    Reference: #{payment.reference_number}\n"
        content += "    Status: #{payment.status.titleize}\n"
        content += "    Notes: #{payment.notes}\n" if payment.notes.present?
        content += "\n"
      end
      content += "-" * 60 + "\n\n"
    end
    
    if quickbooks_id.present?
      content += "QuickBooks Information:\n"
      content += "  QuickBooks ID: #{quickbooks_id}\n"
      content += "  Last Sync: #{last_sync_at&.strftime('%Y-%m-%d %H:%M')}\n\n"
    end
    
    if notes.present?
      content += "Notes:\n#{notes}\n\n"
    end
    
    content += "=" * 60 + "\n"
    content += "Generated on: #{Time.current.strftime('%Y-%m-%d %H:%M')}\n"
    content + "=" * 60
  end
  
  # Check if invoice is partially paid
  def partially_paid?
    total_payments_received > 0 && !paid_in_full?
  end
  
  # Get payment progress for progress bars
  def payment_progress
    {
      percentage: payment_percentage,
      paid: total_payments_received,
      due: balance_due,
      total: amount,
      payments_count: payment_histories.count
    }
  end
  
  # Get integration status for dashboard
  def integration_status
    integrations = []
    integrations << 'quickbooks' if quickbooks_synced?
    integrations << 'pos' if pos_payment_made?
    integrations << 'purchase_order' if has_purchase_order?
    integrations << 'transactions' if has_transactions?
    integrations << 'payment_history' if has_payment_history?
    integrations
  end
  
  # Get timeline of invoice events
  def timeline
    timeline = []
    
    timeline << { event: 'Created', date: created_at, user: created_by, description: "Invoice created" }
    timeline << { event: 'Received', date: received_at, user: received_by, description: "Invoice received" } if received_at
    timeline << { event: 'Reviewed', date: reviewed_at, user: reviewer, description: "Invoice reviewed" } if reviewed?
    
    # Add payment history events
    payment_histories.order(payment_date: :desc).each do |payment|
      timeline << { 
        event: 'Payment Recorded', 
        date: payment.payment_date, 
        description: "Payment of $#{'%.2f' % payment.amount} via #{payment.payment_method}",
        details: { reference: payment.reference_number, status: payment.status }
      }
    end
    
    timeline << { event: 'Marked as Paid', date: paid_at, user: paid_by, description: "Invoice marked as paid" } if paid_at
    timeline << { event: 'Disputed', date: disputed_at, user: disputed_by, description: "Invoice disputed: #{dispute_reason}" } if disputed_at
    timeline << { event: 'QuickBooks Sync', date: last_sync_at, description: "Synced with QuickBooks: #{quickbooks_id}" } if last_sync_at
    
    timeline.sort_by { |event| event[:date] || Time.at(0) }.reverse
  end
  
  # Method to create a payment record (FIXED: removed User.current)
  def record_payment(amount, payment_method, payment_date = Date.current, user = nil, notes = nil)
    # Generate unique reference
    reference = "PAY-#{payment_date.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
    
    # Create transaction first
    transaction = transactions.create!(
      amount: amount,
      payment_method: payment_method,
      reference_number: reference,
      notes: notes || "Payment for invoice #{invoice_number}",
      user: user, # Pass user explicitly, not User.current
      status: :completed,
      transaction_type: :payment
    )
    
    # Create payment history
    payment_history = payment_histories.create!(
      payment_transaction: transaction,
      payment_date: payment_date,
      amount: amount,
      payment_method: payment_method,
      reference_number: reference,
      notes: notes,
      status: :completed
    )
    
    # Update invoice status if fully paid
    if paid_in_full?
      mark_as_paid(user)
    end
    
    payment_history
  end
  
  private
  
  def update_status_based_on_due_date
    if pending? && due_date.present? && due_date < Date.today
      self.status = 'overdue'
    elsif paid_in_full? && status != 'paid'
      self.status = 'paid'
      self.paid_at ||= Time.current
    end
  end
end