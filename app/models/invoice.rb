# app/models/invoice.rb - COMPLETE REVISED VERSION
# FIX: Added before_save callback to auto-update aging_bucket
# FIX: Added after_create callback to create payable from invoice
# FIX: Added can_approve? method for test compatibility
# FIX: Commented out ActivityLog references (model doesn't exist)

class Invoice < ApplicationRecord
  include ActionView::Helpers::DateHelper
  include ActionView::Helpers::NumberHelper

  # ==========================================================
  # ASSOCIATIONS (schema-correct)
  # ==========================================================
  belongs_to :vehicle
  belongs_to :maintenance, optional: true
  belongs_to :purchase_order, optional: true
  belongs_to :pos_transaction, optional: true
  belongs_to :supplier, optional: true
  belongs_to :account, optional: true

  belongs_to :created_by,  class_name: "User", optional: true
  belongs_to :received_by, class_name: "User", optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true
  belongs_to :paid_by,     class_name: "User", optional: true
  belongs_to :disputed_by, class_name: "User", optional: true

  has_many :ledger_entries, dependent: :destroy
  has_many :transactions, dependent: :destroy
  has_many :payment_histories, dependent: :destroy
  # has_many :activity_logs, as: :record, dependent: :destroy  # Commented out - ActivityLog model doesn't exist

  delegate :agency, :agency_id, to: :vehicle, allow_nil: true

  # ==========================================================
  # VALIDATIONS
  # ==========================================================
  validates :invoice_number, presence: true, uniqueness: true
  validates :vehicle_id, :invoice_date, :due_date, :vendor, presence: true
  validates :amount, numericality: { greater_than: 0 }

  # ==========================================================
  # ENUMS
  # ==========================================================
  enum :status, {
    draft: "draft",
    pending: "pending",
    reviewed: "reviewed",
    approved: "approved",
    paid: "paid",
    overdue: "overdue",
    disputed: "disputed",
    cancelled: "cancelled",
    partially_paid: "partially_paid"
  }, default: "pending"

  enum :category, {
    maintenance: "maintenance",
    repair: "repair",
    parts: "parts",
    fuel: "fuel",
    insurance: "insurance",
    licensing: "licensing",
    other: "other"
  }, default: "maintenance"

  enum :priority, { low: "low", medium: "medium", high: "high", critical: "critical" }, default: "medium"

  enum :aging_bucket, {
    current: "current",
    days_30: "30_days",
    days_60: "60_days",
    over_90: "over_90_days"
  }, default: "current"

  enum :sync_status, {
    pending_sync: "pending",
    success: "success",
    failed: "failed",
    error: "error"
  }, default: "pending", prefix: :sync

  enum :payment_terms, {
    net_15: "net_15",
    net_30: "net_30",
    net_45: "net_45",
    net_60: "net_60",
    immediate: "immediate",
    on_receipt: "on_receipt"
  }, default: "net_30"

  # ==========================================================
  # SCOPES - FIXED with explicit table references
  # ==========================================================
  scope :overdue_scope, -> {
    where("#{table_name}.due_date < ? AND #{table_name}.status IN (?)",
          Date.current, %w[draft pending reviewed approved partially_paid])
  }

  scope :pending_scope, -> { where("#{table_name}.status IN (?)", %w[draft pending]) }
  scope :paid_scope, -> { where("#{table_name}.status = ?", "paid") }
  scope :approved_scope, -> { where("#{table_name}.status = ?", "approved") }
  scope :disputed_scope, -> { where("#{table_name}.status = ?", "disputed") }
  scope :reviewed_scope, -> { where("#{table_name}.status = ?", "reviewed") }

  scope :this_month, -> { where("#{table_name}.invoice_date BETWEEN ? AND ?", Time.current.beginning_of_month, Time.current.end_of_month) }
  scope :this_week, -> { where("#{table_name}.invoice_date BETWEEN ? AND ?", Time.current.beginning_of_week, Time.current.end_of_week) }
  scope :today, -> { where("#{table_name}.invoice_date = ?", Date.current) }

  scope :current_aging, -> { where("#{table_name}.aging_bucket = ?", "current") }
  scope :days_30_aging, -> { where("#{table_name}.aging_bucket = ?", "30_days") }
  scope :days_60_aging, -> { where("#{table_name}.aging_bucket = ?", "60_days") }
  scope :over_90_aging, -> { where("#{table_name}.aging_bucket = ?", "over_90_days") }
  scope :by_aging_bucket, ->(bucket) { where("#{table_name}.aging_bucket = ?", bucket) }

  scope :for_agency, ->(agency) {
    joins(:vehicle).where(vehicles: { agency_id: agency.id })
  }
  
  scope :by_service_owner, ->(service_owner) { 
    joins(:vehicle).where(vehicles: { service_owner: service_owner }) 
  }

  scope :with_quickbooks, -> { where.not("#{table_name}.quickbooks_id" => nil) }
  scope :without_quickbooks, -> { where("#{table_name}.quickbooks_id" => nil) }
  scope :with_purchase_order, -> { where.not("#{table_name}.purchase_order_id" => nil) }
  scope :with_pos_payment, -> { where.not("#{table_name}.pos_transaction_id" => nil) }

  scope :has_transactions, -> { joins(:transactions).distinct }
  scope :has_payment_history, -> { joins(:payment_histories).distinct }
  scope :has_ledger_entries, -> { joins(:ledger_entries).distinct }

  scope :recently_synced, ->(hours = 24) { where.not("#{table_name}.last_sync_at" => nil).where("#{table_name}.last_sync_at > ?", hours.hours.ago) }
  scope :sync_stale, -> { where.not("#{table_name}.last_sync_at" => nil).where("#{table_name}.last_sync_at < ?", 7.days.ago) }
  scope :sync_successful, -> { where("#{table_name}.sync_status = ?", "success") }
  scope :sync_failed, -> { where("#{table_name}.sync_status IN (?)", %w[failed error]) }

  scope :reviewed_by_user, -> { where.not("#{table_name}.reviewed_by_id" => nil) }
  scope :unreviewed, -> { where("#{table_name}.reviewed_by_id" => nil) }

  scope :fully_paid, -> { where("#{table_name}.status = ?", "paid") }
  scope :partially_paid_scope, -> { where("#{table_name}.status = ?", "partially_paid") }
  scope :unpaid, -> { where("#{table_name}.status IN (?)", %w[draft pending overdue approved]) }

  scope :eligible_for_bulk_payment, -> {
    where("#{table_name}.status IN (?) AND #{table_name}.amount <= ?", %w[pending overdue partially_paid approved], 100_000)
  }

  scope :by_vendor, ->(vendor) { where("#{table_name}.vendor = ?", vendor) }
  scope :by_supplier, ->(supplier_id) { where("#{table_name}.supplier_id = ?", supplier_id) }
  scope :with_supplier, -> { where.not("#{table_name}.supplier_id" => nil) }

  scope :high_priority, -> { where("#{table_name}.priority IN (?)", %w[high critical]) }
  scope :critical_priority, -> { where("#{table_name}.priority = ?", "critical") }

  # ==========================================================
  # SEARCH
  # ==========================================================
  def self.search(query)
    return all if query.blank?

    joins(:vehicle).where(
      "invoices.invoice_number ILIKE :q
       OR invoices.vendor ILIKE :q
       OR invoices.notes ILIKE :q
       OR vehicles.license_plate ILIKE :q",
      q: "%#{query}%"
    )
  end

  # ==========================================================
  # DISPLAY HELPERS
  # ==========================================================
  def vehicle_display
    return "No vehicle assigned" unless vehicle
    "#{vehicle.license_plate} - #{vehicle.make} #{vehicle.model}"
  end

  def agency_name
    agency&.name || service_owner || vendor
  end

  # ==========================================================
  # UI Helpers
  # ==========================================================
  def status_badge_class
    case status
    when "paid" then "bg-success"
    when "pending" then "bg-primary"
    when "draft" then "bg-secondary"
    when "reviewed" then "bg-info"
    when "approved" then "bg-success"
    when "overdue" then "bg-danger"
    when "disputed" then "bg-warning text-dark"
    when "cancelled" then "bg-dark"
    when "partially_paid" then "bg-info"
    else "bg-light text-dark"
    end
  end

  def aging_badge_class
    case aging_bucket
    when "current" then "bg-success"
    when "30_days" then "bg-warning text-dark"
    when "60_days" then "bg-danger text-white"
    when "over_90_days" then "bg-dark text-white"
    else "bg-secondary"
    end
  end

  def aging_text
    case aging_bucket
    when "current" then "Current (0-29 days)"
    when "30_days" then "30-59 days overdue"
    when "60_days" then "60-89 days overdue"
    when "over_90_days" then "90+ days overdue"
    else "Unknown"
    end
  end

  def priority_badge_class
    case priority
    when "low" then "bg-info"
    when "medium" then "bg-primary"
    when "high" then "bg-warning text-dark"
    when "critical" then "bg-danger"
    else "bg-secondary"
    end
  end

  def urgency_badge_class
    return "bg-danger" if overdue?

    d = days_until_due
    return "bg-secondary" if d.nil?

    if d <= 3
      "bg-danger"
    elsif d <= 7
      "bg-warning"
    elsif d <= 14
      "bg-info"
    else
      "bg-success"
    end
  end

  # ==========================================================
  # PAYMENT HELPERS
  # ==========================================================
  def total_payments_received
    payment_histories.sum(:amount) + transactions.sum(:amount)
  end

  def balance_due
    amount - total_payments_received
  end

  def paid_in_full?
    balance_due <= 0.01
  end

  def partially_paid_amountwise?
    total_payments_received.positive? && !paid_in_full?
  end

  def payment_status
    if paid_in_full?
      "Paid in Full"
    elsif partially_paid_amountwise?
      "Partially Paid"
    else
      "Unpaid"
    end
  end

  def payment_percentage
    return 100 if amount.zero?
    pct = (total_payments_received / amount) * 100
    pct > 100 ? 100 : pct.round(2)
  end

  # ==========================================================
  # VAT (DISPLAY ONLY)
  # ==========================================================
  def vat_rate = 0.125
  def vat_amount = (amount * vat_rate).round(2)
  def total_with_vat = (amount + vat_amount).round(2)
  def subtotal = amount

  # ==========================================================
  # CORE METHODS
  # ==========================================================
  def service_owner
    vehicle&.service_owner
  end

  def days_until_due
    return nil unless due_date
    (due_date - Date.current).to_i
  end

  def calculate_days_overdue
    return 0 unless due_date && !paid? && !cancelled?
    d = (Date.current - due_date).to_i
    d.positive? ? d : 0
  end

  def days_overdue
    calculate_days_overdue
  end

  def calculate_aging_bucket
    d = calculate_days_overdue
    case d
    when 0..29 then "current"
    when 30..59 then "30_days"
    when 60..89 then "60_days"
    else "over_90_days"
    end
  end

  def overdue?
    !paid? && !cancelled? && due_date.present? && due_date < Date.current
  end

  def aging_days
    return nil unless invoice_date
    (Date.current - invoice_date).to_i
  end

  # ==========================================================
  # INTEGRATIONS
  # ==========================================================
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

  def has_ledger_entries?
    ledger_entries.any?
  end

  # ==========================================================
  # SUPPLIER HELPERS
  # ==========================================================
  def supplier_name
    supplier&.name || vendor
  end

  def supplier_contact
    supplier&.contact_person
  end

  def supplier_email
    supplier&.email
  end

  def supplier_phone
    supplier&.phone
  end

  # ==========================================================
  # ADD THIS METHOD FOR TEST COMPATIBILITY
  # ==========================================================
  def can_approve?
    %w[pending reviewed].include?(status) && !paid? && !cancelled?
  end

  # ==========================================================
  # APPROVAL WORKFLOW (CORRECT + SAFE)
  # ==========================================================
  def approve!(user:)
    raise "Invoice already approved" if approved?
    raise "Cannot approve cancelled invoice" if cancelled?
    raise "Invoice amount must be greater than zero" if amount.to_f <= 0

    ApplicationRecord.transaction do
      # mark approved (schema-safe)
      update!(
        reviewed_by: user,
        reviewed_at: Time.current,
        status: "approved"
      )

      post_ledger_entries!(user)

      # ActivityLog.create!(
      #   user: user,
      #   action: "invoice_approved",
      #   description: "Invoice #{invoice_number} approved and posted to ledger",
      #   record: self
      # ) if defined?(ActivityLog)
    end

    true
  end

  # aliases for UI
  def approved_by = reviewed_by
  def approved_at = reviewed_at

  # ==========================================================
  # REVIEW & STATUS HELPERS
  # ==========================================================
  def reviewed?
    reviewed_by.present? || status == "reviewed"
  end

  def reviewer
    reviewed_by || received_by
  end

  # ==========================================================
  # LEDGER POSTING (DOUBLE ENTRY)
  # ==========================================================
  def post_ledger_entries!(user)
    return if ledger_entries.exists?

    LedgerEntry.create!(
      agency_id: agency_id,
      vehicle_id: vehicle_id,
      invoice_id: id,
      posted_by_id: user.id,
      entry_date: Date.current,
      account_code: "6000",
      account_name: "Repairs & Maintenance",
      debit: amount,
      credit: 0,
      memo: "Invoice #{invoice_number}"
    )

    LedgerEntry.create!(
      agency_id: agency_id,
      vehicle_id: vehicle_id,
      invoice_id: id,
      posted_by_id: user.id,
      entry_date: Date.current,
      account_code: "2000",
      account_name: "Accounts Payable",
      debit: 0,
      credit: amount,
      memo: "Invoice #{invoice_number}"
    )
  end

  # ==========================================================
  # SYNC-RELATED METHODS
  # ==========================================================
  def recently_synced?(hours = 24)
    last_sync_at.present? && last_sync_at > hours.hours.ago
  end

  def sync_freshness
    return "Never synced" unless last_sync_at

    if recently_synced?(1)
      "Recently synced"
    elsif recently_synced?(24)
      "Synced today"
    elsif recently_synced?(168)
      "Synced this week"
    else
      "Sync stale"
    end
  end

  def sync_time_ago
    return "Never synced" unless last_sync_at
    "#{time_ago_in_words(last_sync_at)} ago"
  end

  def sync_stale?
    last_sync_at.present? && last_sync_at < 7.days.ago
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

  # ==========================================================
  # INTEGRATION BADGES
  # ==========================================================
  def integration_badges
    badges = []

    if quickbooks_synced?
      badge = { label: "QB", tooltip: "Synced with QuickBooks" }
      if sync_success?
        badge[:color] = recently_synced?(24) ? "success" : "warning"
        badge[:icon] = "check-circle"
      elsif sync_failed?
        badge[:color] = "danger"
        badge[:icon] = "x-circle"
      else
        badge[:color] = "secondary"
        badge[:icon] = "question-circle"
      end
      badges << badge
    end

    badges << { label: "POS", color: "primary", icon: "cash-coin", tooltip: "POS Payment Made" } if pos_payment_made?
    badges << { label: "PO", color: "secondary", icon: "cart-check", tooltip: "Linked to Purchase Order" } if has_purchase_order?
    badges << { label: "PAY", color: "info", icon: "credit-card", tooltip: "Has Transactions" } if has_transactions?
    badges << { label: "HIST", color: "dark", icon: "clock-history", tooltip: "Has Payment History" } if has_payment_history?
    badges << { label: "LEDGER", color: "info", icon: "book", tooltip: "Has Ledger Entries" } if has_ledger_entries?

    if overdue?
      badges << {
        label: "OVERDUE #{days_overdue}d",
        color: aging_badge_class.gsub("bg-", ""),
        icon: "clock",
        tooltip: "Overdue by #{days_overdue} days"
      }
    end

    if priority == "critical"
      badges << {
        label: "CRITICAL",
        color: "danger",
        icon: "exclamation-triangle",
        tooltip: "Critical priority invoice"
      }
    end

    if approved?
      badges << {
        label: "APPROVED",
        color: "success",
        icon: "check-circle",
        tooltip: "Invoice approved"
      }
    end

    badges
  end

  # ==========================================================
  # STATUS TRANSITIONS
  # ==========================================================
  def mark_as_paid(user = nil)
    update!(
      status: "paid",
      paid_by: user,
      paid_at: Time.current
    )
  end

  def mark_as_reviewed(user = nil)
    update!(
      status: "reviewed",
      reviewed_by: user,
      reviewed_at: Time.current
    )
  end

  def mark_as_disputed(user = nil)
    update!(
      status: "disputed",
      disputed_by: user,
      disputed_at: Time.current
    )
  end

  # ==========================================================
  # PAYMENT TIMELINE
  # ==========================================================
  def payment_timeline
    timeline = []

    payment_histories.order(payment_date: :desc).each do |payment|
      timeline << {
        type: "payment",
        date: payment.payment_date,
        amount: payment.amount,
        method: payment.payment_method,
        reference: payment.reference_number,
        notes: payment.notes,
        status: payment.status
      }
    end

    tx_scope = transactions.respond_to?(:completed) ? transactions.completed : transactions
    tx_scope.order(:created_at).each do |t|
      timeline << {
        type: "transaction",
        date: t.created_at.to_date,
        amount: t.amount,
        method: t.payment_method,
        reference: t.reference_number,
        notes: t.notes,
        status: t.status
      }
    end

    timeline << { type: "status_change", date: created_at.to_date, status: "created", notes: "Invoice created" }

    timeline << { type: "status_change", date: reviewed_at.to_date, status: "reviewed", notes: "Invoice reviewed" } if reviewed_at.present?
    timeline << { type: "status_change", date: approved_at.to_date, status: "approved", notes: "Invoice approved" } if approved_at.present?
    timeline << { type: "status_change", date: paid_at.to_date, status: "paid", notes: "Invoice paid" } if paid_at.present?

    timeline.sort_by { |e| e[:date] }.reverse
  end

  def recent_payments(count = 5)
    payment_histories.order(payment_date: :desc).limit(count)
  end

  # ==========================================================
  # QUICKBOOKS SYNC (MOCK)
  # ==========================================================
  def sync_to_quickbooks
    return { success: true, message: "Already synced" } if quickbooks_id.present?

    result = { success: true, quickbooks_id: "QB-#{invoice_number}-#{SecureRandom.hex(8)}" }

    if result[:success]
      update!(
        quickbooks_id: result[:quickbooks_id],
        last_sync_at: Time.current,
        sync_status: "success",
        sync_error: nil
      )

      # ActivityLog.create!(
      #   user: created_by,
      #   action: "quickbooks_sync",
      #   description: "Invoice synced to QuickBooks: #{result[:quickbooks_id]}",
      #   record: self
      # ) if defined?(ActivityLog)

      { success: true, message: "Synced successfully", quickbooks_id: result[:quickbooks_id] }
    else
      update!(sync_status: "failed", sync_error: result[:error], last_sync_at: nil)
      { success: false, error: result[:error] }
    end
  rescue => e
    update!(sync_status: "error", sync_error: e.message, last_sync_at: nil)
    { success: false, error: "QuickBooks sync error: #{e.message}" }
  end

  # ==========================================================
  # TEXT EXPORT
  # ==========================================================
  def to_text
    content = +"=" * 50 + "\n"
    content << "INVOICE RECEIPT\n"
    content << "=" * 50 + "\n\n"

    content << "INVOICE #: #{invoice_number}\n"
    content << "DATE: #{invoice_date&.strftime("%B %d, %Y")}\n"
    content << "DUE DATE: #{due_date&.strftime("%B %d, %Y")}\n"
    content << "VENDOR: #{vendor}\n"
    content << "AGENCY: #{agency_name}\n"
    content << "VEHICLE: #{vehicle_display}\n" if vehicle.present?

    content << "AMOUNT: $#{format("%.2f", amount)}\n"
    content << "VAT (12.5%): $#{format("%.2f", vat_amount)}\n"
    content << "TOTAL: $#{format("%.2f", total_with_vat)}\n"
    content << "STATUS: #{status.humanize.upcase}\n"
    content << "PRIORITY: #{priority.humanize.upcase}\n"
    content << "CATEGORY: #{category.humanize}\n"

    if approved?
      content << "APPROVED BY: #{approved_by&.name}\n"
      content << "APPROVED AT: #{approved_at&.strftime("%Y-%m-%d")}\n"
    end

    content << "OVERDUE: #{days_overdue} days (#{aging_text})\n" if overdue?

    if quickbooks_id.present?
      content << "QUICKBOOKS ID: #{quickbooks_id}\n"
      content << "LAST SYNC: #{last_sync_at&.strftime("%Y-%m-%d") || "Never"}\n"
    end

    content << "=" * 50 + "\n"
    content << "\nNOTES:\n#{notes}\n" if notes.present?

    if payment_histories.any?
      content << "\nPAYMENT HISTORY:\n"
      content << "-" * 50 + "\n"
      payment_histories.order(payment_date: :desc).each do |p|
        content << "- $#{format("%.2f", p.amount)} on #{p.payment_date.strftime("%Y-%m-%d")} via #{p.payment_method} (#{p.reference_number})\n"
      end
      content << "-" * 50 + "\n"
      content << "TOTAL PAID: $#{format("%.2f", total_payments_received)}\n"
      content << "BALANCE DUE: $#{format("%.2f", balance_due)}\n"
    end

    content << "\n" + "=" * 50 + "\n"
    content << "GENERATED: #{Time.current.strftime("%Y-%m-%d %H:%M")}\n"
    content << "=" * 50

    content
  end

  # ==========================================================
  # PROGRESS & STATUS
  # ==========================================================
  def payment_progress
    {
      percentage: payment_percentage,
      paid: total_payments_received,
      due: balance_due,
      total: amount,
      payments_count: payment_histories.count + transactions.count
    }
  end

  def aging_progress
    d = days_overdue
    case aging_bucket
    when "current"
      { percentage: ([d, 29].min / 29.0) * 100, color: "success" }
    when "30_days"
      { percentage: ([(d - 29), 30].min / 30.0) * 100, color: "warning" }
    when "60_days"
      { percentage: ([(d - 59), 30].min / 30.0) * 100, color: "danger" }
    when "over_90_days"
      { percentage: 100, color: "dark" }
    else
      { percentage: 0, color: "secondary" }
    end
  end

  def integration_status
    integrations = []
    integrations << "quickbooks" if quickbooks_synced?
    integrations << "pos" if pos_payment_made?
    integrations << "purchase_order" if has_purchase_order?
    integrations << "transactions" if has_transactions?
    integrations << "payment_history" if has_payment_history?
    integrations << "ledger_entries" if has_ledger_entries?
    integrations << "overdue" if overdue?
    integrations << "approved" if approved?
    integrations << "aging_#{aging_bucket}" if aging_bucket.present?
    integrations << priority if priority != "medium"
    integrations
  end

  def timeline
    t = []
    t << { event: "Created", date: created_at, user: created_by, description: "Invoice created" }
    t << { event: "Received", date: received_at, user: received_by, description: "Invoice received" } if received_at.present?
    t << { event: "Reviewed", date: reviewed_at, user: reviewer, description: "Invoice reviewed" } if reviewed?
    t << { event: "Approved", date: approved_at, user: approved_by, description: "Invoice approved" } if approved?

    payment_histories.order(payment_date: :desc).each do |p|
      t << {
        event: "Payment Recorded",
        date: p.payment_date,
        description: "Payment of #{number_to_currency(p.amount)} via #{p.payment_method}",
        details: { reference: p.reference_number, status: p.status }
      }
    end

    ledger_entries.order(created_at: :desc).each do |e|
      t << {
        event: "Ledger Entry",
        date: e.created_at,
        description: "Ledger entry posted: #{e.account_name}",
        details: { account_code: e.account_code, debit: e.debit, credit: e.credit }
      }
    end

    t << { event: "Marked as Paid", date: paid_at, user: paid_by, description: "Invoice marked as paid" } if paid_at.present?
    t << { event: "Disputed", date: disputed_at, user: disputed_by, description: "Invoice disputed" } if disputed_at.present?
    t << { event: "QuickBooks Sync", date: last_sync_at, description: "Synced with QuickBooks: #{quickbooks_id}" } if last_sync_at.present?
    t << { event: "Became Overdue", date: due_date + 1.day, description: "Invoice became overdue" } if overdue?

    t.sort_by { |ev| ev[:date] || Time.at(0) }.reverse
  end

  # ==========================================================
  # UPDATE METHODS
  # ==========================================================
  def update_aging_information
    return unless overdue?
    update_columns(
      days_overdue: calculate_days_overdue,
      aging_bucket: calculate_aging_bucket
    )
  end

  def update_payment_status
    if paid_in_full?
      mark_as_paid(paid_by)
    elsif partially_paid_amountwise?
      update(status: "partially_paid")
    elsif overdue?
      update(status: "overdue")
    end
  end

  # ==========================================================
  # PAYABLE CREATION - NEW METHOD
  # ==========================================================
  def create_payable_from_invoice
    return if purchase_order.nil?
    return if purchase_order.payable.present?
    
    begin
      payable = Payable.create!(
        purchase_order: purchase_order,
        invoice: self,
        vendor_name: vendor,
        amount: amount,
        amount_due: amount,
        due_date: due_date,
        agency_id: purchase_order.vehicle&.agency_id,
        description: "Invoice #{invoice_number} for PO #{purchase_order.po_number}",
        category: 'purchase_order',
        status: 'open',
        reference_number: "INV-#{invoice_number}"
      )
      
      Rails.logger.info "✅ Payable #{payable.id} created from Invoice #{invoice_number}"
    rescue => e
      Rails.logger.error "❌ Failed to create payable from Invoice #{invoice_number}: #{e.message}"
    end
  end

  # ==========================================================
  # CALLBACKS - FIXED with auto-updating aging_bucket
  # ==========================================================
  before_save :update_overdue_status
  before_save :link_supplier
  before_save :update_aging_bucket  # ← NEW: Auto-update aging bucket before save
  after_save :check_aging_bucket_change, if: :saved_change_to_aging_bucket?
  # after_save :check_status_change_for_logs, if: :saved_change_to_status?  # Commented out - uses ActivityLog
  after_create :create_payable_from_invoice, if: -> { purchase_order.present? }  # ← NEW: Create payable when invoice is created

  private

  def update_overdue_status
    if due_date.present? && due_date < Date.current && !paid? && !cancelled?
      self.status = "overdue" if %w[pending reviewed approved partially_paid].include?(status)
    end
  end

  def link_supplier
    self.supplier = Supplier.find_by(name: vendor) if vendor.present? && supplier.nil?
  end

  # ==========================================================
  # NEW METHOD: Auto-update aging bucket based on days overdue
  # ==========================================================
  def update_aging_bucket
    self.aging_bucket = calculate_aging_bucket
  end

  def check_aging_bucket_change
    return unless defined?(Notification)
    return unless agency.present?

    old_bucket, new_bucket = saved_change_to_aging_bucket
    return unless bucket_became_worse?(old_bucket, new_bucket)

    Notification.create!(
      agency_id: agency.id,
      title: "Invoice #{invoice_number} Aging Alert",
      message: "Invoice #{invoice_number} moved to #{aging_text} bucket",
      link: Rails.application.routes.url_helpers.invoice_path(self),
      priority: "high"
    )
  end

  def bucket_became_worse?(old_bucket, new_bucket)
    severity = {
      "current" => 1,
      "30_days" => 2,
      "60_days" => 3,
      "over_90_days" => 4
    }
    severity.fetch(new_bucket, 0) > severity.fetch(old_bucket, 0)
  end

  # def check_status_change_for_logs
  #   return unless defined?(ActivityLog)
  #
  #   if approved?
  #     ActivityLog.create!(
  #       user: approved_by,
  #       action: "invoice_approved",
  #       description: "Invoice #{invoice_number} approved by #{approved_by&.name}",
  #       record: self
  #     ) if approved_by.present?
  #   end
  # end
end