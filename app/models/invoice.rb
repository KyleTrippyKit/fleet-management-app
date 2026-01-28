# app/models/invoice.rb - COMPLETE FIXED VERSION
class Invoice < ApplicationRecord
  # Associations
  belongs_to :vehicle, optional: true
  belongs_to :maintenance, optional: true
  belongs_to :purchase_order, optional: true
  belongs_to :pos_transaction, optional: true
  belongs_to :rfq, optional: true
  belongs_to :quotation, optional: true
  belongs_to :supplier, optional: true  # NEW: Link to supplier model
  
  # User references
  belongs_to :created_by, class_name: 'User', optional: true, foreign_key: :created_by_id
  belongs_to :received_by, class_name: 'User', optional: true, foreign_key: :received_by_id
  belongs_to :reviewed_by, class_name: 'User', optional: true, foreign_key: :reviewed_by_id
  belongs_to :paid_by, class_name: 'User', optional: true, foreign_key: :paid_by_id
  belongs_to :disputed_by, class_name: 'User', optional: true, foreign_key: :disputed_by_id
  belongs_to :aging_reviewed_by, class_name: 'User', optional: true, foreign_key: :aging_reviewed_by_id
  
  # Payment and transaction associations
  has_many :transactions, dependent: :destroy
  has_many :payment_histories, dependent: :destroy
  has_many :payment_schedules, dependent: :destroy
  
  # Agency delegation through vehicle
  delegate :agency, to: :vehicle, allow_nil: true
  delegate :agency_id, to: :vehicle, allow_nil: true
  delegate :agency_code, to: :vehicle, allow_nil: true
  
  # Activity logs
  has_many :activity_logs, as: :record, dependent: :destroy

  # Validations
  validates :invoice_number, presence: true, uniqueness: true
  validates :vendor, presence: true
  validates :invoice_date, :due_date, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :status, presence: true
  
  # Enums
  enum :status, {
    draft: 'draft',
    pending: 'pending',
    reviewed: 'reviewed',
    paid: 'paid', 
    overdue: 'overdue',
    disputed: 'disputed',
    cancelled: 'cancelled',
    partially_paid: 'partially_paid'
  }, default: 'draft'
  
  enum :category, {
    maintenance: 'maintenance',
    repair: 'repair',
    parts: 'parts',
    fuel: 'fuel',
    insurance: 'insurance',
    licensing: 'licensing',
    cleaning: 'cleaning',
    tires: 'tires',
    electrical: 'electrical',
    mechanical: 'mechanical',
    body_work: 'body_work',
    other: 'other'
  }, default: 'maintenance'
  
  # These enums need database columns or attribute declarations
  enum :priority, {
    low: 'low',
    medium: 'medium',
    high: 'high',
    critical: 'critical'
  }, default: 'medium'
  
  # Aging categories
  enum :aging_bucket, {
    current: 'current',
    days_30: '30_days',
    days_60: '60_days',
    over_90: 'over_90_days'
  }, default: 'current'
  
  # Sync status
  enum :sync_status, {
    pending_sync: 'pending',
    success: 'success',
    failed: 'failed',
    error: 'error'
  }, default: 'pending', prefix: :sync
  
  # Payment terms
  enum :payment_terms, {
    net_15: 'net_15',
    net_30: 'net_30',
    net_45: 'net_45',
    net_60: 'net_60',
    immediate: 'immediate',
    on_receipt: 'on_receipt'
  }, default: 'net_30'
  
  # Scopes
  scope :overdue, -> { where('due_date < ? AND status IN (?)', Date.today, ['draft', 'pending', 'reviewed', 'partially_paid']) }
  scope :pending, -> { where(status: ['draft', 'pending']) }
  scope :paid, -> { where(status: 'paid') }
  scope :disputed, -> { where(status: 'disputed') }
  scope :reviewed, -> { where(status: 'reviewed') }
  scope :this_month, -> { where(invoice_date: Time.current.beginning_of_month..Time.current.end_of_month) }
  scope :this_week, -> { where(invoice_date: Time.current.beginning_of_week..Time.current.end_of_week) }
  scope :today, -> { where(invoice_date: Date.today) }
  
  # Aging scopes
  scope :current_aging, -> { where(aging_bucket: 'current') }
  scope :days_30_aging, -> { where(aging_bucket: '30_days') }
  scope :days_60_aging, -> { where(aging_bucket: '60_days') }
  scope :over_90_aging, -> { where(aging_bucket: 'over_90_days') }
  scope :by_aging_bucket, ->(bucket) { where(aging_bucket: bucket) }
  
  # Agency isolation scopes
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
  scope :has_payment_history, -> { joins(:payment_histories).distinct }
  
  # Sync scopes
  scope :recently_synced, ->(hours = 24) { 
    where.not(last_sync_at: nil).where('last_sync_at > ?', hours.hours.ago) 
  }
  scope :sync_stale, -> { 
    where.not(last_sync_at: nil).where('last_sync_at < ?', 7.days.ago) 
  }
  scope :sync_successful, -> { where(sync_status: 'success') }
  scope :sync_failed, -> { where(sync_status: ['failed', 'error']) }
  
  # Review scopes
  scope :reviewed, -> { where.not(reviewed_by_id: nil) }
  scope :unreviewed, -> { where(reviewed_by_id: nil) }
  
  # Payment scopes
  scope :fully_paid, -> { where(status: 'paid') }
  scope :partially_paid, -> { 
    where(status: 'partially_paid')
  }
  scope :unpaid, -> { where(status: ['draft', 'pending', 'overdue']) }
  
  # Bulk payment scopes
  scope :eligible_for_bulk_payment, -> { 
    where(status: ['pending', 'overdue', 'partially_paid'])
      .where('amount <= ?', 100000) # Cap for bulk payments
  }
  
  # Vendor scopes
  scope :by_vendor, ->(vendor) { where(vendor: vendor) }
  
  # Supplier scopes (NEW)
  scope :by_supplier, ->(supplier_id) { where(supplier_id: supplier_id) }
  scope :with_supplier, -> { where.not(supplier_id: nil) }
  
  # Priority scopes
  scope :high_priority, -> { where(priority: ['high', 'critical']) }
  scope :critical, -> { where(priority: 'critical') }
  
  # Search
  def self.search(query)
    return all if query.blank?
    
    joins(:vehicle).where(
      "invoices.invoice_number ILIKE :q OR invoices.vendor ILIKE :q OR invoices.notes ILIKE :q OR vehicles.license_plate ILIKE :q",
      q: "%#{query}%"
    )
  end
  
  # Status badge helper for views
  def status_badge_class
    case status
    when 'paid'
      'bg-success'
    when 'pending'
      'bg-primary'
    when 'draft'
      'bg-secondary'
    when 'reviewed'
      'bg-info'
    when 'overdue'
      'bg-danger'
    when 'disputed'
      'bg-warning text-dark'
    when 'cancelled'
      'bg-dark'
    when 'partially_paid'
      'bg-info'
    else
      'bg-light text-dark'
    end
  end
  
  # Aging badge helper
  def aging_badge_class
    case aging_bucket
    when 'current'
      'bg-success'
    when '30_days'
      'bg-warning text-dark'
    when '60_days'
      'bg-danger text-white'
    when 'over_90_days'
      'bg-dark text-white'
    else
      'bg-secondary'
    end
  end
  
  # Aging text
  def aging_text
    case aging_bucket
    when 'current'
      "Current (0-29 days)"
    when '30_days'
      "30-59 days overdue"
    when '60_days'
      "60-89 days overdue"
    when 'over_90_days'
      "90+ days overdue"
    else
      "Unknown"
    end
  end
  
  # Priority badge
  def priority_badge_class
    case priority
    when 'low'
      'bg-info'
    when 'medium'
      'bg-primary'
    when 'high'
      'bg-warning text-dark'
    when 'critical'
      'bg-danger'
    else
      'bg-secondary'
    end
  end
  
  # Urgency badge helper for views (based on days until due)
  def urgency_badge_class
    return 'bg-danger' if overdue?
    
    if days_until_due.present?
      if days_until_due <= 3
        'bg-danger'
      elsif days_until_due <= 7
        'bg-warning'
      elsif days_until_due <= 14
        'bg-info'
      else
        'bg-success'
      end
    else
      'bg-secondary'
    end
  end
  
  # Get service owner from vehicle
  def service_owner
    vehicle&.service_owner
  end
  
  # Get agency name
  def agency_name
    agency&.name || service_owner || vendor
  end
  
  # Days until due (negative if overdue)
  def days_until_due
    return nil unless due_date
    (due_date - Date.today).to_i
  end
  
  # Days overdue calculation
  def calculate_days_overdue
    return 0 unless due_date && !paid? && !cancelled?
    overdue_days = (Date.today - due_date).to_i
    overdue_days > 0 ? overdue_days : 0
  end
  
  # Calculate aging bucket
  def calculate_aging_bucket
    days_overdue = calculate_days_overdue
    
    case days_overdue
    when 0..29
      'current'
    when 30..59
      '30_days'
    when 60..89
      '60_days'
    else
      'over_90_days'
    end
  end
  
  # Check if invoice is overdue
  def overdue?
    !paid? && !cancelled? && due_date.present? && due_date < Date.today
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
  
  # Payment calculations
  def total_payments_received
    payment_histories.completed.sum(:amount) + transactions.completed.sum(:amount)
  end
  
  def balance_due
    amount - total_payments_received
  end
  
  def paid_in_full?
    balance_due <= 0.01 # Allow for rounding errors
  end
  
  def partially_paid?
    total_payments_received > 0 && !paid_in_full?
  end
  
  def payment_status
    if paid_in_full?
      'Paid in Full'
    elsif partially_paid?
      'Partially Paid'
    else
      'Unpaid'
    end
  end
  
  # Payment percentage
  def payment_percentage
    return 100 if amount.zero?
    percentage = (total_payments_received / amount) * 100
    percentage > 100 ? 100 : percentage.round(2)
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
  
  # Supplier methods (NEW)
  def supplier_name
    supplier&.name || vendor
  end
  
  def supplier_contact
    supplier&.contact_person if supplier
  end
  
  def supplier_email
    supplier&.email if supplier
  end
  
  def supplier_phone
    supplier&.phone if supplier
  end
  
  # Aging status for reports
  def aging_status
    {
      days_overdue: days_overdue,
      aging_bucket: aging_bucket,
      is_overdue: overdue?,
      is_critical: days_overdue > 90
    }
  end
  
  # Sync-related methods
  def recently_synced?(hours = 24)
    last_sync_at.present? && last_sync_at > hours.hours.ago
  end
  
  def sync_freshness
    return "Never synced" unless last_sync_at
    
    if recently_synced?(1)
      "Recently synced"
    elsif recently_synced?(24)
      "Synced today"
    elsif recently_synced?(168) # 7 days
      "Synced this week"
    else
      "Sync stale"
    end
  end
  
  def sync_time_ago
    return "Never synced" unless last_sync_at
    "#{time_ago_in_words(last_sync_at)} ago"
  end
  
  def sync_status_badge
    return unless quickbooks_id.present?
    
    if sync_success?
      if recently_synced?(1)
        { label: "Recently Synced", color: "success", icon: "check-circle-fill" }
      elsif recently_synced?(24)
        { label: "Synced Today", color: "info", icon: "check-circle" }
      elsif recently_synced?(168)
        { label: "Synced This Week", color: "warning", icon: "clock" }
      else
        { label: "Sync Stale", color: "secondary", icon: "exclamation-triangle" }
      end
    elsif sync_failed?
      { label: "Sync Failed", color: "danger", icon: "x-circle" }
    elsif sync_error?
      { label: "Sync Error", color: "danger", icon: "exclamation-triangle-fill" }
    else
      { label: "Pending Sync", color: "warning", icon: "clock-history" }
    end
  end
  
  def sync_stale?
    last_sync_at.present? && last_sync_at < 7.days.ago
  end
  
  def integration_badges
    badges = []
    
    if quickbooks_synced?
      badge = { label: 'QB', tooltip: 'Synced with QuickBooks' }
      if sync_success?
        badge[:color] = recently_synced?(24) ? 'success' : 'warning'
        badge[:icon] = 'check-circle'
      elsif sync_failed?
        badge[:color] = 'danger'
        badge[:icon] = 'x-circle'
      else
        badge[:color] = 'secondary'
        badge[:icon] = 'question-circle'
      end
      badges << badge
    end
    
    badges << { label: 'POS', color: 'primary', icon: 'cash-coin', tooltip: 'POS Payment Made' } if pos_payment_made?
    badges << { label: 'PO', color: 'secondary', icon: 'cart-check', tooltip: 'Linked to Purchase Order' } if has_purchase_order?
    badges << { label: 'PAY', color: 'info', icon: 'credit-card', tooltip: 'Has Transactions' } if has_transactions?
    badges << { label: 'HIST', color: 'dark', icon: 'clock-history', tooltip: 'Has Payment History' } if has_payment_history?
    
    if overdue?
      badges << { 
        label: "OVERDUE #{days_overdue}d", 
        color: aging_badge_class.gsub('bg-', ''), 
        icon: 'clock', 
        tooltip: "Overdue by #{days_overdue} days" 
      }
    end
    
    if priority == 'critical'
      badges << { 
        label: "CRITICAL", 
        color: 'danger', 
        icon: 'exclamation-triangle', 
        tooltip: 'Critical priority invoice' 
      }
    end
    
    badges
  end
  
  # Mark methods
  def mark_as_paid(user = nil)
    update!(
      status: 'paid', 
      paid_by: user, 
      paid_at: Time.current,
      last_payment_date: Time.current
    )
    
    # Create activity log
    ActivityLog.create!(
      user: user,
      action: 'invoice_paid',
      description: "Invoice #{invoice_number} marked as paid",
      record: self
    ) if defined?(ActivityLog)
  end
  
  def mark_as_reviewed(user = nil)
    update!(
      status: 'reviewed',
      reviewed_by: user, 
      reviewed_at: Time.current
    )
    
    # Create activity log
    ActivityLog.create!(
      user: user,
      action: 'invoice_reviewed',
      description: "Invoice #{invoice_number} reviewed",
      record: self
    ) if defined?(ActivityLog)
  end
  
  def mark_as_disputed(reason = nil, user = nil)
    update!(
      status: 'disputed',
      disputed_by: user,
      disputed_at: Time.current,
      dispute_reason: reason
    )
    
    # Create activity log
    ActivityLog.create!(
      user: user,
      action: 'invoice_disputed',
      description: "Invoice #{invoice_number} disputed: #{reason}",
      record: self
    ) if defined?(ActivityLog)
  end

  def mark_as_aging_reviewed(user = nil)
    update!(
      aging_reviewed_at: Time.current,
      aging_reviewed_by: user
    )
    
    # Create activity log
    ActivityLog.create!(
      user: user,
      action: 'invoice_aging_reviewed',
      description: "Aging reviewed for invoice #{invoice_number}",
      record: self
    ) if defined?(ActivityLog)
  end

  # VAT calculation methods
  def vat_rate
    0.125 # 12.5% Trinidad VAT rate
  end

  def vat_amount
    (amount * vat_rate).round(2)
  end

  def total_with_vat
    (amount * (1 + vat_rate)).round(2)
  end

  def subtotal
    amount
  end
  
  # Days overdue
  def days_overdue
    calculate_days_overdue
  end
  
  # Check if invoice has been reviewed
  def reviewed?
    reviewed_by.present? || status == 'reviewed'
  end
  
  # Get the user who reviewed the invoice
  def reviewer
    reviewed_by || received_by
  end
  
  # Get review timestamp
  def reviewed_at
    self[:reviewed_at] || received_at
  end
  
  # Aging review status
  def aging_reviewed?
    aging_reviewed_at.present?
  end
  
  # Aging review user
  def aging_reviewer
    aging_reviewed_by
  end
  
  # Payment timeline
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
    
    # Add transaction entries
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
    
    # Add status changes
    timeline << {
      type: 'status_change',
      date: created_at.to_date,
      status: 'created',
      notes: "Invoice created"
    }
    
    timeline << {
      type: 'status_change',
      date: reviewed_at.to_date,
      status: 'reviewed',
      notes: "Invoice reviewed"
    } if reviewed_at
    
    timeline << {
      type: 'status_change',
      date: paid_at.to_date,
      status: 'paid',
      notes: "Invoice paid"
    } if paid_at
    
    timeline.sort_by { |entry| entry[:date] }.reverse
  end
  
  def recent_payments(count = 5)
    payment_histories.order(payment_date: :desc).limit(count)
  end
  
  # QuickBooks sync
  def sync_to_quickbooks
    return { success: true, message: 'Already synced' } if quickbooks_id.present?
    
    begin
      # Mock QuickBooks integration
      # In production, you would call the actual QuickBooks API
      result = { success: true, quickbooks_id: "QB-#{invoice_number}-#{SecureRandom.hex(8)}" }
      
      if result[:success]
        update!(
          quickbooks_id: result[:quickbooks_id],
          last_sync_at: Time.current,
          sync_status: 'success',
          sync_error: nil
        )
        
        # Create activity log
        ActivityLog.create!(
          user: created_by,
          action: 'quickbooks_sync',
          description: "Invoice synced to QuickBooks: #{result[:quickbooks_id]}",
          record: self
        ) if defined?(ActivityLog)
        
        { success: true, message: 'Synced successfully', quickbooks_id: result[:quickbooks_id] }
      else
        update!(
          sync_status: 'failed',
          sync_error: result[:error],
          last_sync_at: nil
        )
        { success: false, error: result[:error] }
      end
    rescue => e
      update!(
        sync_status: 'error',
        sync_error: e.message,
        last_sync_at: nil
      )
      { success: false, error: "QuickBooks sync error: #{e.message}" }
    end
  end
  
  # Generate invoice text for download
  def to_text
    content = "=" * 50 + "\n"
    content += "INVOICE RECEIPT\n"
    content += "=" * 50 + "\n\n"
    
    content += "INVOICE #: #{invoice_number}\n"
    content += "DATE: #{invoice_date&.strftime('%B %d, %Y')}\n"
    content += "DUE DATE: #{due_date&.strftime('%B %d, %Y')}\n"
    content += "VENDOR: #{vendor}\n"
    content += "AGENCY: #{agency_name}\n"
    
    if vehicle.present?
      content += "VEHICLE: #{vehicle_display}\n"
    end
    
    content += "AMOUNT: $#{'%.2f' % amount}\n"
    content += "VAT (12.5%): $#{'%.2f' % vat_amount}\n"
    content += "TOTAL: $#{'%.2f' % total_with_vat}\n"
    content += "STATUS: #{status.humanize.upcase}\n"
    content += "PRIORITY: #{priority.humanize.upcase}\n"
    content += "CATEGORY: #{category.humanize}\n"
    
    if overdue?
      content += "OVERDUE: #{days_overdue} days (#{aging_text})\n"
    end
    
    if quickbooks_id.present?
      content += "QUICKBOOKS ID: #{quickbooks_id}\n"
      content += "LAST SYNC: #{last_sync_at&.strftime('%Y-%m-%d') || 'Never'}\n"
    end
    
    content += "=" * 50 + "\n"
    
    if notes.present?
      content += "\nNOTES:\n#{notes}\n"
    end
    
    # Payment history
    if payment_histories.any?
      content += "\nPAYMENT HISTORY:\n"
      content += "-" * 50 + "\n"
      payment_histories.order(payment_date: :desc).each do |payment|
        content += "- $#{'%.2f' % payment.amount} on #{payment.payment_date.strftime('%Y-%m-%d')} via #{payment.payment_method} (#{payment.reference_number})\n"
      end
      
      total_paid = total_payments_received
      balance = balance_due
      
      content += "-" * 50 + "\n"
      content += "TOTAL PAID: $#{'%.2f' % total_paid}\n"
      content += "BALANCE DUE: $#{'%.2f' % balance}\n"
      
      if overdue?
        content += "OVERDUE BALANCE: $#{'%.2f' % balance}\n"
      end
    end
    
    content += "\n" + "=" * 50 + "\n"
    content += "GENERATED: #{Time.current.strftime('%Y-%m-%d %H:%M')}\n"
    content += "=" * 50
    
    content
  end
  
  # Get payment progress for progress bars
  def payment_progress
    {
      percentage: payment_percentage,
      paid: total_payments_received,
      due: balance_due,
      total: amount,
      payments_count: payment_histories.count + transactions.count
    }
  end
  
  # Aging progress for aging reports
  def aging_progress
    days = days_overdue
    
    case aging_bucket
    when 'current'
      { percentage: [days, 29].min / 29.0 * 100, color: 'success' }
    when '30_days'
      { percentage: [(days - 29), 30].min / 30.0 * 100, color: 'warning' }
    when '60_days'
      { percentage: [(days - 59), 30].min / 30.0 * 100, color: 'danger' }
    when 'over_90_days'
      { percentage: 100, color: 'dark' }
    else
      { percentage: 0, color: 'secondary' }
    end
  end
  
  # Get integration status for dashboard
  def integration_status
    integrations = []
    integrations << 'quickbooks' if quickbooks_synced?
    integrations << 'pos' if pos_payment_made?
    integrations << 'purchase_order' if has_purchase_order?
    integrations << 'transactions' if has_transactions?
    integrations << 'payment_history' if has_payment_history?
    integrations << 'overdue' if overdue?
    integrations << "aging_#{aging_bucket}" if aging_bucket.present?
    integrations << priority if priority != 'medium'
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
    timeline << { event: 'Became Overdue', date: due_date + 1.day, description: "Invoice became overdue" } if overdue?
    timeline << { event: 'Aging Reviewed', date: aging_reviewed_at, user: aging_reviewer, description: "Aging reviewed" } if aging_reviewed?
    
    timeline.sort_by { |event| event[:date] || Time.at(0) }.reverse
  end
  
  # Method to create a payment record
  def record_payment(amount, payment_method, payment_date = Date.current, user = nil, notes = nil)
    # Generate unique reference
    reference = "PAY-#{payment_date.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
    
    # Create payment history
    payment_history = payment_histories.create!(
      payment_date: payment_date,
      amount: amount,
      payment_method: payment_method,
      reference_number: reference,
      notes: notes,
      status: 'completed',
      recorded_by: user
    )
    
    # Update invoice status
    update_payment_status
    
    # Create activity log
    ActivityLog.create!(
      user: user,
      action: 'payment_recorded',
      description: "Recorded payment of #{number_to_currency(amount)} for invoice #{invoice_number}",
      record: self,
      details: { 
        amount: amount, 
        payment_method: payment_method, 
        reference: reference,
        notes: notes
      }
    ) if defined?(ActivityLog)
    
    payment_history
  end
  
  # Bulk payment processing
  def self.process_bulk_payment(invoice_ids, payment_method, payment_date, user, notes = nil)
    ActiveRecord::Base.transaction do
      total_amount = 0
      processed_invoices = []
      errors = []
      
      Invoice.where(id: invoice_ids).each do |invoice|
        begin
          # Record payment
          invoice.record_payment(
            invoice.balance_due,
            payment_method,
            payment_date,
            user,
            "Bulk payment - #{notes}"
          )
          
          total_amount += invoice.balance_due
          processed_invoices << invoice
        rescue => e
          errors << "Failed to pay invoice #{invoice.invoice_number}: #{e.message}"
        end
      end
      
      if errors.any?
        raise ActiveRecord::Rollback
        return {
          success: false,
          error: errors.join(', '),
          processed_count: processed_invoices.count,
          total_amount: total_amount
        }
      end
      
      # Create bulk payment record
      bulk_payment = BulkPayment.create!(
        agency_id: user.agency_id,
        user: user,
        total_amount: total_amount,
        payment_method: payment_method,
        payment_date: payment_date,
        notes: notes,
        invoice_count: processed_invoices.count,
        invoice_ids: processed_invoices.map(&:id),
        reference_number: "BULK-#{payment_date.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
      )
      
      # Create activity log
      ActivityLog.create!(
        user: user,
        action: 'bulk_payment_processed',
        description: "Processed bulk payment for #{processed_invoices.count} invoices totaling #{number_to_currency(total_amount)}",
        record: bulk_payment,
        details: {
          invoice_count: processed_invoices.count,
          total_amount: total_amount,
          payment_method: payment_method
        }
      ) if defined?(ActivityLog)
      
      {
        success: true,
        total_amount: total_amount,
        invoice_count: processed_invoices.count,
        processed_invoices: processed_invoices,
        bulk_payment: bulk_payment
      }
    end
  rescue => e
    {
      success: false,
      error: e.message
    }
  end
  
  # Update aging information
  def update_aging_information
    return unless overdue?
    
    new_days_overdue = calculate_days_overdue
    new_aging_bucket = calculate_aging_bucket
    
    update_columns(
      days_overdue: new_days_overdue,
      aging_bucket: new_aging_bucket
    )
  end
  
  # Update payment status based on payments
  def update_payment_status
    if paid_in_full?
      mark_as_paid(paid_by)
    elsif partially_paid?
      update(status: 'partially_paid')
    elsif overdue?
      update(status: 'overdue')
    end
  end
  
  # Callbacks
  before_save :update_status_based_on_due_date
  before_save :update_aging_information, if: :due_date_changed?
  before_save :link_supplier  # NEW: Link supplier from vendor field
  
  after_save :check_aging_bucket_change, if: :saved_change_to_aging_bucket?
  
  private
  
  def update_status_based_on_due_date
    if pending? && due_date.present? && due_date < Date.today
      self.status = 'overdue'
    elsif paid_in_full? && status != 'paid'
      self.status = 'paid'
      self.paid_at ||= Time.current
    end
  end
  
  # NEW: Link supplier from vendor field
  def link_supplier
    if vendor.present? && supplier.nil?
      self.supplier = Supplier.find_by(name: vendor)
    end
  end
  
  def check_aging_bucket_change
    # Notify when invoice moves to a worse aging bucket
    if saved_change_to_aging_bucket? && aging_bucket_became_worse?
      # Create notification for critical aging changes
      if agency.present?
        Notification.create!(
          agency_id: agency.id,
          title: "Invoice #{invoice_number} Aging Alert",
          message: "Invoice #{invoice_number} moved to #{aging_text} bucket",
          link: Rails.application.routes.url_helpers.invoice_path(self),
          priority: 'high'
        ) if defined?(Notification)
      end
    end
  end
  
  def aging_bucket_became_worse?
    old_bucket, new_bucket = saved_change_to_aging_bucket
    
    # Define bucket severity order
    bucket_severity = {
      'current' => 1,
      '30_days' => 2,
      '60_days' => 3,
      'over_90_days' => 4
    }
    
    bucket_severity[new_bucket] > bucket_severity[old_bucket]
  end
end