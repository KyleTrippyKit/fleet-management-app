# app/models/purchase_order.rb
# frozen_string_literal: true

class PurchaseOrder < ApplicationRecord
  # -------------------------
  # Associations
  # -------------------------
  belongs_to :vehicle, optional: true
  belongs_to :created_by, class_name: 'User'
  belongs_to :approved_by, class_name: 'User', optional: true
  belongs_to :rejected_by, class_name: 'User', optional: true
  belongs_to :payment_authorized_by, class_name: 'User', optional: true
  belongs_to :payment_processed_by, class_name: 'User', optional: true

  belongs_to :quotation, optional: true
  belongs_to :supplier, optional: true

  # Link to vendor quotation
  has_one :vendor_quotation, dependent: :nullify

  has_one :payable, dependent: :destroy

  has_many :purchase_order_items, dependent: :destroy
  has_many :invoices, dependent: :nullify
  has_many :payment_histories, as: :payment_transaction
  has_many :payment_audits, dependent: :destroy
  has_many :vendor_invoices

  # Link to internal POS (VMCOTT internal work orders)
  has_many :internal_pos, class_name: 'InternalPos', dependent: :nullify

  accepts_nested_attributes_for :purchase_order_items,
                                allow_destroy: true,
                                reject_if: proc { |attributes|
                                  attributes['description'].blank? && attributes['quantity'].blank?
                                }

  # Smart delegation - vehicle's agency becomes PO's agency
  delegate :agency, to: :vehicle, allow_nil: true
  delegate :agency_id, to: :vehicle, allow_nil: true

  # -------------------------
  # Enums - MUST MATCH SCHEMA (all strings in DB)
  # -------------------------
  # STATUS ENUM - Order lifecycle only (string in DB)
  enum :status, {
    draft: 'draft',
    pending_approval: 'pending_approval',
    approved: 'approved',
    rejected: 'rejected',
    ordered: 'ordered',
    received: 'received',
    cancelled: 'cancelled',
    paid: 'paid'
  }, default: 'draft'

  # PAYMENT STATUS ENUM - Payment lifecycle only (string in DB)
  enum :payment_status, {
    unpaid: 'unpaid',
    pending: 'pending',
    processing: 'processing',
    authorized: 'authorized',
    completed: 'completed',
    failed: 'failed',
    refunded: 'refunded'
  }, default: 'unpaid'

  enum :payment_method, {
    cash: 'cash',
    cheque: 'cheque',
    bank_transfer: 'bank_transfer',
    trinidad_debit_card: 'trinidad_debit_card',
    trinidad_credit_card: 'trinidad_credit_card',
    debit_card: 'debit_card',
    credit_card: 'credit_card',
    other: 'other'
  }

  # ACCEPTANCE STATUS ENUM - String values (matches schema)
  enum :acceptance_status, {
    pending_acceptance: 'pending_acceptance',
    fully_accepted: 'fully_accepted',
    fully_rejected: 'fully_rejected'
  }, default: 'pending_acceptance'

  # VMCOTT STATUS ENUM - String values (matches schema)
  enum :vmcott_status, {
    pending_internal_work: 'pending_internal_work',
    work_in_progress: 'work_in_progress',
    internal_work_completed: 'internal_work_completed',
    ready_for_delivery: 'ready_for_delivery',
    delivered: 'delivered'
  }, default: 'pending_internal_work'

  # -------------------------
  # Validations
  # -------------------------
  validates :po_number, presence: true, uniqueness: true
  validates :vendor, presence: true
  validates :amount, numericality: { greater_than_or_equal_to: 0 }
  validates :status, presence: true
  validates :payment_status, presence: true
  
  # Custom validations
  validate :cannot_cancel_if_paid, if: :cancelled?

  # -------------------------
  # Scopes
  # -------------------------
  scope :recent, -> { order(created_at: :desc) }
  
  scope :for_agency, ->(agency_id) { joins(:vehicle).where(vehicles: { agency_id: agency_id }) }
  scope :by_creator, ->(user_id) { where(created_by_id: user_id) if user_id.present? }

  # Acceptance scopes
  scope :awaiting_acceptance, -> { where(acceptance_status: 'pending_acceptance') }
  scope :fully_accepted, -> { where(acceptance_status: 'fully_accepted') }
  scope :fully_rejected, -> { where(acceptance_status: 'fully_rejected') }
  scope :pending_vmcott_review, -> { where(vendor: 'VMCOTT', acceptance_status: 'pending_acceptance') }

  # VMCOTT scopes
  scope :pending_internal_work, -> { where(vmcott_status: 'pending_internal_work') }
  scope :work_in_progress, -> { where(vmcott_status: 'work_in_progress') }
  scope :ready_for_delivery, -> { where(vmcott_status: 'ready_for_delivery') }
  scope :has_internal_pos, -> { where.not(vmcott_status: 'pending_internal_work') }

  # Status scopes
  scope :pending_approval, -> { where(status: 'pending_approval') }
  scope :needs_payment, -> { where(status: 'approved', payment_status: 'unpaid') }
  scope :ordered, -> { where(status: 'ordered') }
  scope :received, -> { where(status: 'received') }

  # Payment status scopes
  scope :unpaid, -> { where(payment_status: ['unpaid', 'failed']) }
  scope :paid, -> { where(payment_status: 'completed') }
  scope :payment_pending, -> { where(payment_status: ['pending', 'processing', 'authorized']) }

  # Active purchase orders
  scope :active, -> { where.not(status: ['cancelled', 'paid']).where.not(payment_status: 'completed') }

  # Trinidad card payments
  scope :trinidad_card_payments, -> { where(payment_method: ['trinidad_debit_card', 'trinidad_credit_card']) }
  scope :successful_trinidad_payments, -> { trinidad_card_payments.where(payment_status: 'completed') }
  scope :failed_trinidad_payments, -> { trinidad_card_payments.where(payment_status: 'failed') }

  # From quotation scope
  scope :from_quotation, ->(quotation_id) { where(quotation_id: quotation_id) }

  # Supplier scopes
  scope :by_supplier, ->(supplier_id) { where(supplier_id: supplier_id) }
  scope :with_supplier, -> { where.not(supplier_id: nil) }

  # -------------------------
  # Amount Calculations
  # -------------------------

  def line_items_total
    purchase_order_items.sum("COALESCE(quantity,0) * COALESCE(unit_price,0)")
  end

  def accepted_amount
    purchase_order_items.where(is_accepted: true).sum(:total_price)
  end

  def rejected_amount
    purchase_order_items.where(is_accepted: false).sum(:total_price)
  end

  def recalculate_amount!
    update!(amount: line_items_total)
  end

  # -------------------------
  # SIMPLIFIED ACCEPTANCE METHODS - Whole PO only!
  # -------------------------

  def fully_accepted?
    acceptance_status == 'fully_accepted'
  end

  def fully_rejected?
    acceptance_status == 'fully_rejected'
  end

  def pending_acceptance?
    acceptance_status == 'pending_acceptance'
  end

  # Method for VMCOTT to accept entire PO (what they'll use 99% of the time)
  def accept_entire_po!(user = nil)
    transaction do
      # Mark all items as accepted
      purchase_order_items.update_all(is_accepted: true, rejection_reason: nil)
      
      # Update PO status
      update!(
        acceptance_status: 'fully_accepted',
        acceptance_acknowledged_at: Time.current
      )
      
      # 🔥 NEW: Automatically create work orders
      create_auto_work_orders(user)
      
      # 🔥 NEW: Auto-start work if eligible
      auto_start_work(user) if should_auto_start?
    end
  end

  # 🔥 NEW: Auto-create work orders
  def create_auto_work_orders(user)
    return unless defined?(InternalPos)
    return if internal_pos.exists? # Don't create duplicates
    
    # Create main workshop work order
    workshop_po = internal_pos.create!(
      work_order_number: InternalPos.generate_work_order_number,
      created_by: user,
      status: 'pending',
      priority: determine_priority,
      notes: "[Work Section: Workshop]\n[Work Role: Technician]\nMain repair work for PO #{po_number}\nVehicle: #{vehicle&.license_plate}"
    )
    
    # Create QC inspection work order (always)
    qc_po = internal_pos.create!(
      work_order_number: InternalPos.generate_work_order_number,
      created_by: user,
      status: 'pending',
      priority: 'normal',
      notes: "[Work Section: QC / Inspection]\n[Work Role: QC Inspector]\nQuality inspection required for PO #{po_number}"
    )
    
    # Create billing work order for larger jobs
    if amount > 2000
      internal_pos.create!(
        work_order_number: InternalPos.generate_work_order_number,
        created_by: user,
        status: 'pending',
        priority: 'normal',
        notes: "[Work Section: Billing]\n[Work Role: Billing Officer]\nPrepare final invoice for PO #{po_number}"
      )
    end
    
    # Send notification to workshop
    notify_workshop("New work orders created for PO #{po_number}")
    
    Rails.logger.info "✅ Created #{internal_pos.count} work orders for PO #{po_number}"
  end

  # 🔥 NEW: Auto-start work
  def auto_start_work(user)
    # Find the workshop work order and start it
    workshop_po = internal_pos.find_by('notes LIKE ?', '%[Work Section: Workshop]%')
    
    if workshop_po
      workshop_po.update!(status: 'in_progress')
      update!(vmcott_status: 'work_in_progress')
      
      notify_workshop("Work started on PO #{po_number}")
      Rails.logger.info "▶️ Auto-started work on PO #{po_number}"
    end
  end

  # 🔥 NEW: Determine if work should auto-start
  def should_auto_start?
    # Auto-start jobs under $3000, manual for larger ones
    amount < 3000
  end

  # 🔥 NEW: Determine priority based on amount
  def determine_priority
    if amount >= 5000
      'high'
    elsif amount >= 2000
      'normal'
    else
      'low'
    end
  end

  # 🔥 NEW: Notify workshop
  def notify_workshop(message)
    Rails.logger.info "📢 WORKSHOP: #{message}"
    
    # If you have a Notification model, uncomment:
    # Notification.create!(
    #   recipient_type: 'workshop',
    #   title: 'Work Order Update',
    #   message: message,
    #   link: "/vmcott/internal_pos",
    #   priority: 'medium'
    # )
  end

  # 🔥 NEW: Notify agency
  def notify_agency(message)
    return unless agency_id
    
    Rails.logger.info "📢 AGENCY #{agency&.code}: #{message}"
    
    # If you have agency notifications:
    # AgencyNotification.create!(
    #   agency_id: agency_id,
    #   title: 'Purchase Order Update',
    #   message: message,
    #   link: "/purchase_orders/#{id}"
    # )
  end

  # Method for VMCOTT to reject entire PO (rare - only if parts missing or can't do work)
  def reject_entire_po!(reason = nil, user = nil)
    transaction do
      # Mark all items as rejected with reason
      purchase_order_items.update_all(
        is_accepted: false, 
        rejection_reason: reason
      )
      
      # Update PO status
      update!(
        acceptance_status: 'fully_rejected',
        rejection_reason: reason,
        rejected_at: Time.current,
        rejected_by: user,
        status: 'rejected'  # Also update main status to rejected
      )
    end
  end

  # Simple check if any items are pending
  def any_items_pending?
    purchase_order_items.where(is_accepted: nil).any?
  end

  # -------------------------
  # VMCOTT Workflow Methods (After Acceptance)
  # -------------------------

  def mark_work_in_progress!(user = nil)
    update!(vmcott_status: 'work_in_progress')
  end

  def mark_internal_work_completed!(user = nil)
    update!(vmcott_status: 'internal_work_completed')
  end

  def mark_ready_for_delivery!(user = nil)
    update!(vmcott_status: 'ready_for_delivery')
  end

  def mark_delivered!(user = nil)
    update!(vmcott_status: 'delivered')
  end

  def has_internal_pos?
    internal_pos.any?
  end

  def internal_work_in_progress?
    vmcott_status == 'work_in_progress'
  end

  def internal_work_completed?
    vmcott_status == 'internal_work_completed'
  end

  # -------------------------
  # VMCOTT Internal POS Creation (Optional)
  # -------------------------

  def create_internal_pos(assigned_to_id, estimated_completion_date, notes, user)
    return unless defined?(InternalPos)

    ActiveRecord::Base.transaction do
      internal_po = InternalPos.create!(
        purchase_order_id: id,
        assigned_to_id: assigned_to_id,
        estimated_completion_date: estimated_completion_date,
        status: 'pending',
        priority: 'normal',
        notes: notes,
        created_by: user
      )

      update!(vmcott_status: 'work_in_progress')
      internal_po
    end
  end

  # -------------------------
  # Agency State Machine Methods
  # -------------------------

  def submit_for_approval!
    update!(status: 'pending_approval')
  end

  def approve!(user = nil)
    transaction do
      update!(
        status: 'approved',
        approved_by: user,
        approved_at: Time.current,
        due_date: calculate_due_date
      )
      # Payable will be created when needed
    end
  end

  def reject!(user = nil, reason = nil)
    update!(
      status: 'rejected',
      rejected_by: user,
      rejection_reason: reason,
      rejected_at: Time.current
    )
  end

  def cancel!(reason = nil)
    transaction do
      update!(
        status: 'cancelled',
        notes: [notes, "Cancelled on #{Date.today}: #{reason}"].compact.join("\n")
      )
      
      if payable.present?
        payable.update(status: 'cancelled')
      end
    end
  end

  def mark_ordered!
    update!(
      status: 'ordered',
      ordered_at: Time.current
    )
  end

  def mark_received!
    update!(
      status: 'received',
      received_at: Time.current
    )
  end

  # -------------------------
  # Payment Methods
  # -------------------------

  def can_initiate_payment?
    status == 'approved' && 
    (unpaid? || pending? || processing?) && 
    fully_accepted?
  end

  def can_authorize_payment?
    pending? && is_trinidad_payment?
  end

  def can_complete_payment?
    authorized? && is_trinidad_payment?
  end

  def is_trinidad_payment?
    payment_method == 'trinidad_debit_card' || payment_method == 'trinidad_credit_card'
  end

  alias_method :is_trinidad_card_payment?, :is_trinidad_payment?

  def payment_initiated?
    payment_initiated_at.present?
  end

  def payment_authorized?
    payment_authorized_at.present?
  end

  def payment_failed?
    payment_failed_at.present?
  end

  def mark_as_paid!(reference:, method:, user:, notes: nil, last_four_digits: nil, card_type: nil)
    update!(
      payment_status: 'completed',
      payment_method: method,
      payment_reference: reference,
      paid_at: Time.current,
      payment_date: Time.current,
      payment_notes: notes,
      last_four_digits: last_four_digits,
      card_type: card_type,
      status: 'paid'
    )

    auto_create_invoice_if_paid
  end

  def initiate_trinidad_card_payment!(user, card_details, billing_address)
    return false unless can_initiate_payment?
    
    # Use mock payment service for development
    update!(
      payment_method: card_details[:card_type] == 'debit' ? 'trinidad_debit_card' : 'trinidad_credit_card',
      card_type: card_details[:card_brand],
      last_four_digits: card_details[:last_four],
      payment_reference: "TRN-#{SecureRandom.hex(8).upcase}",
      billing_address: billing_address.to_json,
      payment_status: 'pending',
      payment_initiated_at: Time.current,
      payment_processed_by_id: user.id
    )
    
    # Create payment history
    payment_histories.create!(
      amount: amount,
      payment_date: Time.current,
      payment_method: card_details[:card_type] == 'debit' ? 'trinidad_debit_card' : 'trinidad_credit_card',
      reference_number: payment_reference,
      status: 'processing',
      notes: "Trinidad card payment initiated for PO #{po_number}"
    )
    
    true
  rescue => e
    errors.add(:base, "Payment initiation failed: #{e.message}")
    false
  end

  def authorize_trinidad_payment!(user)
    return false unless payment_status == 'pending'
    
    update!(
      payment_status: 'authorized',
      payment_authorized_at: Time.current,
      payment_authorized_by_id: user.id
    )
    
    true
  end

  def complete_trinidad_payment!
    return false unless payment_status == 'authorized'
    
    update!(
      payment_status: 'completed',
      status: 'paid',
      payment_date: Time.current,
      paid_at: Time.current
    )
    
    # Update payment history
    payment_histories.update_all(status: 'completed')
    
    # Create invoice
    auto_create_invoice_if_paid
    
    true
  end

  # -------------------------
  # Payable-related methods
  # -------------------------

  def calculate_due_date
    return due_date if due_date.present?

    case payment_terms
    when 'net_15'
      (created_at + 15.days).to_date
    when 'net_30'
      (created_at + 30.days).to_date
    when 'net_45'
      (created_at + 45.days).to_date
    when 'net_60'
      (created_at + 60.days).to_date
    when 'due_on_receipt'
      Date.current
    else
      (created_at + 30.days).to_date
    end
  end

  def create_payable!
    return payable if payable.present?
    return nil unless defined?(Payable)

    agency_id_value = vehicle&.agency_id
    
    raise "PurchaseOrder #{id} has no agency_id (vehicle missing or vehicle has no agency)" if agency_id_value.blank?
    raise "PurchaseOrder #{id} has no vendor" if vendor.blank?
    raise "PurchaseOrder #{id} has invalid amount (#{amount.inspect})" if amount.blank? || amount.to_f <= 0

    payable_account = Account.payable_accounts
                             .for_agency(agency_id_value)
                             .first_or_create!(
                               account_number: '2000',
                               name: 'Accounts Payable',
                               account_type: 'liability',
                               sub_type: 'accounts_payable',
                               agency_id: agency_id_value
                             )

    Payable.create!(
      purchase_order_id: id,
      vendor_name: vendor,
      agency_id: agency_id_value,
      amount: amount,
      amount_due: amount,
      due_date: due_date || calculate_due_date,
      account_id: payable_account.id,
      description: "Purchase Order #{po_number} - #{vendor}",
      category: 'purchase_order',
      status: 'open'
    )
  end

  # -------------------------
  # Business Logic Methods
  # -------------------------

  def editable?
    draft? || pending_approval?
  end

  def can_be_paid?
    approved? && unpaid? && fully_accepted?
  end

  def can_be_approved?
    pending_approval?
  end

  def can_create_internal_pos?
    status == 'approved' && fully_accepted?
  end
  
  def can_cancel?
    return true if payable.blank?
    payable.status != 'paid'
  end

  def update_amount_from_items
    calculate_amount_from_items
    save if changed?
  end

  def update_total_amount
    total = purchase_order_items.sum("COALESCE(quantity,0) * COALESCE(unit_price,0)")
    if self.class.column_names.include?("amount")
      update_column(:amount, total)
    elsif self.class.column_names.include?("total_amount")
      update_column(:total_amount, total)
    end
  end

  def billing_address_hash
    return {} if billing_address.blank?
    JSON.parse(billing_address)
  rescue JSON::ParserError
    {}
  end

  def notify_vendor_of_acceptance
    return unless quotation.present?

    if defined?(PurchaseOrderMailer)
      PurchaseOrderMailer.acceptance_notification(self).deliver_later
    end

    if quotation.processing_agency.present? && defined?(Notification)
      Notification.create!(
        agency_id: quotation.processing_agency_id,
        title: "PO #{po_number} Accepted",
        message: "Purchase Order #{po_number} has been accepted by #{agency&.name}",
        link: Rails.application.routes.url_helpers.purchase_order_path(self),
        priority: 'medium'
      )
    end
  end

  # -------------------------
  # Analytics Methods
  # -------------------------

  def self.trinidad_payment_stats(time_range: 30.days.ago..Time.current, agency_id: nil)
    payments = trinidad_card_payments.where(created_at: time_range).order(created_at: :asc)
    payments = payments.for_agency(agency_id) if agency_id.present?

    successful = payments.successful_trinidad_payments
    failed = payments.failed_trinidad_payments

    {
      total_transactions: payments.count,
      total_amount: payments.sum(:amount),
      successful_count: successful.count,
      failed_count: failed.count,
      success_rate: payments.count > 0 ? (successful.count.to_f / payments.count * 100).round(2) : 0
    }
  end

  def self.search(query)
    return all if query.blank?
    where("po_number ILIKE :q OR vendor ILIKE :q", q: "%#{query}%")
  end

  # -------------------------
  # CSV Export Methods
  # -------------------------
  def self.to_csv
    attributes = %w[
      po_number vendor amount status payment_status acceptance_status 
      vmcott_status created_at updated_at payment_method payment_reference
    ]
    
    CSV.generate(headers: true) do |csv|
      csv << attributes.map(&:humanize)
      
      all.find_each do |po|
        csv << attributes.map { |attr| po.send(attr) }
      end
    end
  end

  def self.to_xlsx
    # For now, return nil or raise a helpful error
    # If you want Excel support, add 'axlsx' gem to Gemfile
    raise "Excel export requires the 'axlsx' gem. Please add it to your Gemfile or use CSV export instead."
  end

  # -------------------------
  # Print/PDF methods
  # -------------------------

  def print_data
    {
      po_number: po_number,
      vendor: vendor,
      amount: sprintf('$%.2f', amount),
      accepted_amount: sprintf('$%.2f', accepted_amount),
      date: created_at.strftime('%B %d, %Y'),
      status: display_status,
      payment_status: display_payment_status,
      acceptance_status: display_acceptance_status,
      vmcott_status: display_vmcott_status,
      vehicle: display_vehicle,
      items: purchase_order_items.map do |item|
        {
          description: item.description,
          quantity: item.quantity,
          unit_price: sprintf('$%.2f', item.unit_price),
          total: sprintf('$%.2f', item.quantity * item.unit_price),
          accepted: item.is_accepted,
          rejection_reason: item.rejection_reason
        }
      end,
      line_items_total: sprintf('$%.2f', line_items_total),
      accepted_items_total: sprintf('$%.2f', accepted_amount),
      created_by_name: created_by&.name || 'System',
      approved_by_name: approved_by&.name,
      notes: notes
    }
  end

  def to_pdf
    html = ApplicationController.render(
      template: 'purchase_orders/print',
      layout: 'pdf',
      assigns: { purchase_order: self }
    )

    WickedPdf.new.pdf_from_string(
      html,
      margin: { top: 15, bottom: 15, left: 10, right: 10 },
      header: {
        content: ApplicationController.render(
          template: 'purchase_orders/_pdf_header',
          layout: false,
          assigns: { purchase_order: self }
        )
      },
      footer: {
        content: ApplicationController.render(
          template: 'purchase_orders/_pdf_footer',
          layout: false,
          assigns: { purchase_order: self }
        )
      },
      orientation: 'Portrait',
      page_size: 'A4',
      encoding: 'UTF-8'
    )
  end

  def pdf_filename
    "Purchase_Order_#{po_number}.pdf"
  end

  def has_pdf?
    pdf_s3_url.present?
  end

  # ============================================
  # DISPLAY METHODS & BADGES
  # ============================================

  # Badge color methods
  def status_badge_color
    case status
    when 'draft' then 'secondary'
    when 'pending_approval' then 'warning'
    when 'approved' then 'success'
    when 'rejected' then 'danger'
    when 'ordered' then 'info'
    when 'received' then 'primary'
    when 'cancelled' then 'dark'
    when 'paid' then 'success'
    else 'secondary'
    end
  end

  def payment_status_badge_color
    case payment_status
    when 'unpaid' then 'danger'
    when 'pending' then 'warning'
    when 'processing' then 'info'
    when 'authorized' then 'primary'
    when 'completed' then 'success'
    when 'failed' then 'dark'
    when 'refunded' then 'secondary'
    else 'secondary'
    end
  end

  def acceptance_badge_color
    case acceptance_status
    when 'fully_accepted' then 'success'
    when 'fully_rejected' then 'danger'
    when 'pending_acceptance' then 'secondary'
    else 'secondary'
    end
  end

  def vmcott_status_badge_color
    case vmcott_status
    when 'pending_internal_work' then 'secondary'
    when 'work_in_progress' then 'warning'
    when 'internal_work_completed' then 'info'
    when 'ready_for_delivery' then 'primary'
    when 'delivered' then 'success'
    else 'secondary'
    end
  end

  # Icon methods
  def status_icon
    case status
    when 'draft' then 'file'
    when 'pending_approval' then 'clock'
    when 'approved' then 'check-circle'
    when 'ordered' then 'paper-plane'
    when 'received' then 'eye'
    when 'paid' then 'receipt'
    when 'cancelled' then 'ban'
    when 'rejected' then 'times-circle'
    else 'circle'
    end
  end

  def vmcott_status_icon
    case vmcott_status
    when 'pending_internal_work' then 'hourglass-half'
    when 'work_in_progress' then 'tools'
    when 'internal_work_completed' then 'check-double'
    when 'ready_for_delivery' then 'truck'
    when 'delivered' then 'check-circle'
    else 'circle'
    end
  end

  # Description methods
  def status_description
    case status
    when 'draft' then 'This is a draft - not yet submitted for approval'
    when 'pending_approval' then 'Awaiting supervisor approval before sending to VMCOTT'
    when 'approved' then 'Approved and ready to send to VMCOTT'
    when 'ordered' then 'Sent to VMCOTT - awaiting their review'
    when 'received' then 'Work completed - awaiting your review and payment'
    when 'paid' then 'Payment completed - order is closed'
    when 'cancelled' then 'This order was cancelled'
    when 'rejected' then 'This order was rejected'
    else 'Status unknown'
    end
  end

  def vmcott_status_description
    case vmcott_status
    when 'pending_internal_work' then 'Order received - waiting to start work'
    when 'work_in_progress' then 'Vehicle is currently being worked on'
    when 'internal_work_completed' then 'Work is finished - ready to prepare for delivery'
    when 'ready_for_delivery' then 'Vehicle is ready for pickup/delivery'
    when 'delivered' then 'Vehicle has been delivered to the agency'
    else 'Status unknown'
    end
  end

  def acceptance_status_description
    case acceptance_status
    when 'pending_acceptance' then 'Waiting for VMCOTT to review and accept/reject'
    when 'fully_accepted' then 'All items accepted - work can begin'
    when 'fully_rejected' then 'All items rejected - order cancelled'
    else 'Status unknown'
    end
  end

  def payment_status_description
    case payment_status
    when 'unpaid' then 'Payment has not been initiated'
    when 'pending' then 'Payment is being processed'
    when 'processing' then 'Payment is being processed by the bank'
    when 'authorized' then 'Payment authorized - waiting to complete'
    when 'completed' then 'Payment completed successfully'
    when 'failed' then 'Payment failed - please try again'
    when 'refunded' then 'Payment has been refunded'
    else 'Status unknown'
    end
  end

  # Display methods
  def display_status
    status&.humanize&.titleize || 'Draft'
  end

  def display_payment_status
    payment_status&.humanize&.titleize || 'Unpaid'
  end

  def display_acceptance_status
    case acceptance_status
    when 'fully_accepted' then 'Accepted'
    when 'fully_rejected' then 'Rejected'
    when 'pending_acceptance' then 'Pending Acceptance'
    else acceptance_status.humanize.titleize
    end
  end

  def display_vmcott_status
    case vmcott_status
    when 'pending_internal_work' then 'Pending Work'
    when 'work_in_progress' then 'Work in Progress'
    when 'internal_work_completed' then 'Work Completed'
    when 'ready_for_delivery' then 'Ready for Delivery'
    when 'delivered' then 'Delivered'
    else vmcott_status.humanize.titleize
    end
  end

  def display_payment_method
    if payment_method.present?
      payment_method.humanize.titleize.gsub('Trinidad ', '🇹🇹 ')
    else
      'Not Paid'
    end
  end

  def display_payment_date
    paid_at&.strftime('%b %d, %Y %I:%M %p') || 'Not paid'
  end

  def display_created_date
    created_at.strftime('%b %d, %Y')
  end

  def display_created_time_ago
    time_ago_in_words(created_at) + ' ago'
  end

  def total_items
    purchase_order_items.sum(:quantity)
  end

  def display_vehicle
    vehicle ? "#{vehicle.license_plate} - #{vehicle.make} #{vehicle.model}" : 'No Vehicle'
  end

  def acceptance_summary
    total = purchase_order_items.count
    accepted = purchase_order_items.where(is_accepted: true).count
    rejected = purchase_order_items.where(is_accepted: false).count

    if fully_accepted?
      "All #{total} items accepted"
    elsif fully_rejected?
      "All #{total} items rejected"
    else
      "Accepted: #{accepted}/#{total} • Rejected: #{rejected}/#{total}"
    end
  end

  def internal_work_summary
    return "No internal POS" unless has_internal_pos?

    completed = internal_pos.where(status: 'completed').count
    total = internal_pos.count

    "POS: #{completed}/#{total} completed"
  end

  def compliance_checked?
    compliance_checked.present? && compliance_checked
  end

  # Payment method helpers
  def payment_method_icon
    case payment_method
    when 'bank_transfer' then 'fa-university'
    when 'cheque' then 'fa-money-check'
    when 'cash' then 'fa-money-bill-wave'
    when 'debit_card', 'trinidad_debit_card' then 'fa-credit-card'
    when 'credit_card', 'trinidad_credit_card' then 'fa-credit-card'
    else 'fa-money-bill-alt'
    end
  end

  def payment_method_badge_color
    case payment_method
    when 'trinidad_debit_card', 'trinidad_credit_card' then 'primary'
    when 'debit_card', 'credit_card' then 'info'
    when 'bank_transfer' then 'success'
    when 'cheque' then 'warning'
    when 'cash' then 'secondary'
    else 'dark'
    end
  end

  # Utility methods
  def vmcott_progress_percentage
    case vmcott_status
    when 'pending_internal_work' then 0
    when 'work_in_progress' then 33
    when 'internal_work_completed' then 66
    when 'ready_for_delivery' then 90
    when 'delivered' then 100
    else 0
    end
  end

  def priority_level
    if amount >= 5000
      'high'
    elsif amount >= 2000
      'medium'
    else
      'low'
    end
  end

  def priority_badge_color
    case priority_level
    when 'high' then 'danger'
    when 'medium' then 'warning'
    else 'success'
    end
  end

  def priority_icon
    case priority_level
    when 'high' then 'exclamation-triangle'
    when 'medium' then 'clock'
    else 'check-circle'
    end
  end

  # Timeline Events
  def timeline_events
    events = []
    
    events << {
      date: created_at,
      title: "Purchase Order Created",
      description: "PO #{po_number} was created by #{created_by&.name || 'System'}",
      icon: 'file-plus',
      color: 'primary'
    }
    
    if ordered_at
      events << {
        date: ordered_at,
        title: "Sent to VMCOTT",
        description: "Order was sent to VMCOTT for processing",
        icon: 'paper-plane',
        color: 'info'
      }
    end
    
    if acceptance_acknowledged_at
      events << {
        date: acceptance_acknowledged_at,
        title: "Accepted by VMCOTT",
        description: "VMCOTT accepted the order and started work",
        icon: 'check-circle',
        color: 'success'
      }
    end
    
    if rejected_at
      events << {
        date: rejected_at,
        title: "Rejected by VMCOTT",
        description: rejection_reason || "Order was rejected",
        icon: 'times-circle',
        color: 'danger'
      }
    end
    
    if vmcott_status == 'work_in_progress' && acceptance_acknowledged_at
      events << {
        date: acceptance_acknowledged_at + 1.hour,
        title: "Work Started",
        description: "VMCOTT began working on the vehicle",
        icon: 'tools',
        color: 'warning'
      }
    end
    
    if internal_work_completed?
      events << {
        date: updated_at,
        title: "Work Completed",
        description: "All work on the vehicle has been finished",
        icon: 'check-double',
        color: 'info'
      }
    end
    
    if ready_for_delivery?
      events << {
        date: updated_at,
        title: "Ready for Delivery",
        description: "Vehicle is ready to be picked up",
        icon: 'truck',
        color: 'primary'
      }
    end
    
    if delivered?
      events << {
        date: updated_at,
        title: "Delivered",
        description: "Vehicle has been delivered to the agency",
        icon: 'check-circle',
        color: 'success'
      }
    end
    
    if paid_at
      events << {
        date: paid_at,
        title: "Payment Completed",
        description: "Payment of #{ActionController::Base.helpers.number_to_currency(amount)} was processed",
        icon: 'receipt',
        color: 'success'
      }
    end
    
    events.sort_by { |e| e[:date] }.reverse
  end

  # -------------------------
  # Convenience methods
  # -------------------------

  def payment_unpaid?
    unpaid?
  end

  def payment_pending?
    pending?
  end

  def payment_processing?
    processing?
  end

  def payment_authorized?
    authorized?
  end

  def payment_completed?
    completed?
  end

  def payment_failed?
    failed?
  end

  def payment_refunded?
    refunded?
  end

  # -------------------------
  # Recompute acceptance status
  # -------------------------

  def recompute_acceptance_status!
    total_items = purchase_order_items.count
    return if total_items == 0

    accepted_count = purchase_order_items.where(is_accepted: true).count
    rejected_count = purchase_order_items.where(is_accepted: false).count
    
    new_status = if accepted_count == total_items
                   'fully_accepted'
                 elsif rejected_count == total_items
                   'fully_rejected'
                 else
                   'pending_acceptance'
                 end
    
    update!(acceptance_status: new_status) unless acceptance_status == new_status
  end

  # -------------------------
  # Callbacks
  # -------------------------

  before_validation :generate_po_number, on: :create
  before_validation :set_default_statuses, on: :create
  before_validation :calculate_amount_from_items, if: -> { purchase_order_items.present? }
  before_save :link_supplier

  after_update :auto_create_invoice_if_paid
  after_update :create_payment_audit_trail, if: :saved_change_to_payment_status?

  # -------------------------
  # Private Methods
  # -------------------------

  private

  def generate_po_number
    return if po_number.present?

    date_prefix = Date.current.strftime('%Y%m%d')
    last_po = PurchaseOrder.where('po_number LIKE ?', "#{date_prefix}-%")
                          .order(created_at: :desc)
                          .first

    if last_po
      last_number = last_po.po_number.split('-').last.to_i
      self.po_number = "#{date_prefix}-#{format('%03d', last_number + 1)}"
    else
      self.po_number = "#{date_prefix}-001"
    end
  end

  def set_default_statuses
    self.status = 'draft' if status.blank?
    self.payment_status = 'unpaid' if payment_status.blank?
    self.acceptance_status = 'pending_acceptance' if acceptance_status.blank?
    self.vmcott_status = 'pending_internal_work' if vmcott_status.blank?
  end

  def calculate_amount_from_items
    return if purchase_order_items.blank?
    self.amount = purchase_order_items.sum("COALESCE(quantity,0) * COALESCE(unit_price,0)")
  end

  def link_supplier
    return if vendor.blank? || supplier.present?
    self.supplier = Supplier.find_by(name: vendor)
  end

  def auto_create_invoice_if_paid
    return unless saved_change_to_payment_status?
    return unless payment_status == 'completed'
    return if invoices.exists?

    invoices.create!(
      invoice_number: "INV-#{po_number}",
      vendor: vendor,
      amount: amount,
      status: 'paid',
      invoice_date: Date.current,
      due_date: Date.current,
      vehicle_id: vehicle_id,
      created_by: created_by,
      notes: "Auto-generated from Purchase Order #{po_number}"
    )
  end

  def create_payment_audit_trail
    return unless payment_initiated_at.present?
    return unless is_trinidad_payment?
    return unless defined?(PaymentAudit) && PaymentAudit.respond_to?(:create_audit_trail)
    PaymentAudit.create_audit_trail(self)
  end
  
  def cannot_cancel_if_paid
    if payable.present? && payable.status == 'paid'
      errors.add(:base, "Cannot cancel a purchase order that has been paid")
    end
  end
end