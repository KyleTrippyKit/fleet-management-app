# app/models/invoice.rb
class Invoice < ApplicationRecord
  # Associations
  belongs_to :vehicle, optional: true
  belongs_to :maintenance, optional: true
  belongs_to :purchase_order, optional: true
  belongs_to :pos_transaction, optional: true
  
  # User references - ADD reviewed_by association
  belongs_to :created_by, class_name: 'User', optional: true, foreign_key: :created_by_id
  belongs_to :received_by, class_name: 'User', optional: true, foreign_key: :received_by_id
  belongs_to :reviewed_by, class_name: 'User', optional: true, foreign_key: :reviewed_by_id  # ADD THIS LINE
  belongs_to :paid_by, class_name: 'User', optional: true, foreign_key: :paid_by_id
  belongs_to :disputed_by, class_name: 'User', optional: true, foreign_key: :disputed_by_id
  
  # New associations for integrations
  has_many :transactions, dependent: :destroy
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
  
  scope :by_service_owner, ->(owner) { 
    if owner.present?
      joins(:vehicle).where(vehicles: { service_owner: owner })
    else
      all
    end
  }
  
  # Integration scopes
  scope :with_quickbooks, -> { where.not(quickbooks_id: nil) }
  scope :without_quickbooks, -> { where(quickbooks_id: nil) }
  scope :with_purchase_order, -> { where.not(purchase_order_id: nil) }
  scope :with_pos_payment, -> { where.not(pos_transaction_id: nil) }
  scope :has_transactions, -> { joins(:transactions).distinct }
  
  # Add reviewed/unreviewed scopes
  scope :reviewed, -> { where.not(reviewed_by_id: nil) }
  scope :unreviewed, -> { where(reviewed_by_id: nil) }
  
  # Callbacks
  before_save :update_status_based_on_due_date
  
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
      'bg-warning text-dark'
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
  def agency
    service_owner
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
  
  # Get agency name for display
  def agency_name
    service_owner || 'Unknown Agency'
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
  
  # Payment methods
  def total_paid
    transactions.completed.sum(:amount) + (pos_transaction&.amount || 0)
  end
  
  def balance_due
    amount - total_paid
  end
  
  def paid_in_full?
    balance_due <= 0
  end
  
  def payment_status
    if paid_in_full?
      'Paid in Full'
    elsif total_paid > 0
      'Partially Paid'
    else
      'Unpaid'
    end
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
  
  def integration_badges
    badges = []
    badges << { label: 'QB', color: 'success', icon: 'check-circle', tooltip: 'Synced with QuickBooks' } if quickbooks_synced?
    badges << { label: 'POS', color: 'primary', icon: 'cash-coin', tooltip: 'POS Payment Made' } if pos_payment_made?
    badges << { label: 'PO', color: 'secondary', icon: 'cart-check', tooltip: 'Linked to Purchase Order' } if has_purchase_order?
    badges << { label: 'PAY', color: 'info', icon: 'credit-card', tooltip: 'Has Transactions' } if has_transactions?
    badges
  end
  
  # Payment percentage
  def payment_percentage
    return 0 if amount.zero?
    ((total_paid / amount) * 100).round(2)
  end
  
  # Mark methods
  def mark_as_paid(user = nil)
    update!(
      status: 'paid', 
      paid_by: user, 
      paid_at: Time.current
    )
  end
  
  # Update mark_as_reviewed to use reviewed_by instead of received_by
  def mark_as_reviewed(user = nil)
    update!(
      received_by: user, 
      received_at: Time.current
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
    # Enhanced text version
    content = "=" * 60 + "\n"
    content += "INVOICE\n"
    content += "=" * 60 + "\n\n"
    
    content += "Invoice Details:\n"
    content += "  Invoice #: #{invoice_number}\n"
    content += "  Date: #{invoice_date}\n"
    content += "  Due Date: #{due_date}\n"
    content += "  Status: #{status.upcase}\n\n"
    
    content += "Vendor Information:\n"
    content += "  Vendor: #{vendor}\n"
    content += "  Agency: #{agency_name}\n\n"
    
    content += "Vehicle Information:\n"
    content += "  Vehicle: #{vehicle_display}\n"
    content += "  Category: #{category.titleize}\n\n"
    
    content += "Financial Information:\n"
    content += "  Total Amount: $#{'%.2f' % amount}\n"
    content += "  Amount Paid: $#{'%.2f' % total_paid}\n"
    content += "  Balance Due: $#{'%.2f' % balance_due}\n"
    content += "  Payment Status: #{payment_status}\n\n"
    
    if quickbooks_id.present?
      content += "QuickBooks Information:\n"
      content += "  QuickBooks ID: #{quickbooks_id}\n"
      content += "  Last Sync: #{last_sync_at&.strftime('%Y-%m-%d %H:%M')}\n\n"
    end
    
    if notes.present?
      content += "Notes:\n#{notes}\n\n"
    end
    
    if transactions.any?
      content += "Payment History:\n"
      content += "-" * 40 + "\n"
      transactions.order(:created_at).each_with_index do |transaction, index|
        content += "#{index + 1}. $#{'%.2f' % transaction.amount} on #{transaction.created_at.strftime('%Y-%m-%d')}\n"
        content += "   Method: #{transaction.payment_method.titleize}\n"
        content += "   Ref: #{transaction.reference_number}\n"
        content += "   Notes: #{transaction.notes}\n" if transaction.notes.present?
        content += "\n"
      end
    end
    
    content += "=" * 60 + "\n"
    content += "Generated on: #{Time.current.strftime('%Y-%m-%d %H:%M')}\n"
    content + "=" * 60
  end
  
  # Check if invoice is partially paid
  def partially_paid?
    total_paid > 0 && !paid_in_full?
  end
  
  # Get payment progress for progress bars
  def payment_progress
    {
      percentage: payment_percentage,
      paid: total_paid,
      due: balance_due,
      total: amount
    }
  end
  
  # Get integration status for dashboard
  def integration_status
    integrations = []
    integrations << 'quickbooks' if quickbooks_synced?
    integrations << 'pos' if pos_payment_made?
    integrations << 'purchase_order' if has_purchase_order?
    integrations << 'transactions' if has_transactions?
    integrations
  end
  
  # Get timeline of invoice events
  def timeline
    timeline = []
    
    timeline << { event: 'Created', date: created_at, user: created_by, description: "Invoice created" }
    timeline << { event: 'Received', date: received_at, user: received_by, description: "Invoice received" } if received_at
    timeline << { event: 'Reviewed', date: reviewed_at, user: reviewer, description: "Invoice reviewed" } if reviewed?
    timeline << { event: 'Payment', date: paid_at, user: paid_by, description: "Invoice marked as paid" } if paid_at
    timeline << { event: 'Disputed', date: disputed_at, user: disputed_by, description: "Invoice disputed: #{dispute_reason}" } if disputed_at
    timeline << { event: 'QuickBooks Sync', date: last_sync_at, description: "Synced with QuickBooks: #{quickbooks_id}" } if last_sync_at
    
    # Add transaction events
    transactions.order(:created_at).each do |transaction|
      timeline << { event: 'Payment Recorded', date: transaction.created_at, user: transaction.user, description: "Payment of $#{'%.2f' % transaction.amount} via #{transaction.payment_method}" }
    end
    
    timeline.sort_by { |event| event[:date] || Time.at(0) }
  end
  
  # Method to create a transaction from invoice
  def create_payment(amount, payment_method, user, notes = nil)
    transactions.create!(
      amount: amount,
      payment_method: payment_method,
      reference_number: "PAY-#{Time.now.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}",
      notes: notes || "Payment for invoice #{invoice_number}",
      user: user
    )
  end
  
  private
  
  def update_status_based_on_due_date
    if pending? && due_date.present? && due_date < Date.today
      self.status = 'overdue'
    end
  end
end