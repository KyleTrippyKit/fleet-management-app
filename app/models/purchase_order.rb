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
  validate :must_have_payable_when_approved, if: :approved?
  validate :cannot_cancel_if_paid, if: :cancelled?

  # -------------------------
  # Scopes
  # -------------------------
  scope :recent, -> { order(created_at: :desc) }
  
  scope :for_agency, ->(agency_id) { joins(:vehicle).where(vehicles: { agency_id: agency_id }) }

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
      
      # Automatically start work when accepted
      mark_work_in_progress!(user) if user
    end
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

  # Simple check if any items are pending (shouldn't happen in simplified workflow)
  def any_items_pending?
    purchase_order_items.where(is_accepted: nil).any?
  end

  # -------------------------
  # VMCOTT Workflow Methods (After Acceptance)
  # -------------------------

  def mark_work_in_progress!(user)
    update!(vmcott_status: 'work_in_progress')
  end

  def mark_internal_work_completed!(user)
    update!(vmcott_status: 'internal_work_completed')
  end

  def mark_ready_for_delivery!(user)
    update!(vmcott_status: 'ready_for_delivery')
  end

  def mark_delivered!(user)
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
      ensure_payable!
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

  def ensure_payable!
    return payable if payable.present?
    create_payable!
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
    billing_address.is_a?(Hash) ? billing_address : {}
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

  # -------------------------
  # View Helpers & Badges
  # -------------------------

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
  # Callbacks
  # -------------------------

  before_validation :generate_po_number, on: :create
  before_validation :set_default_statuses, on: :create
  before_validation :calculate_amount_from_items, if: -> { purchase_order_items.present? }
  before_save :link_supplier
  before_save :ensure_payable_for_approved_status, if: :will_save_change_to_status?

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
  
  def ensure_payable_for_approved_status
    if status == 'approved' && payable.blank?
      begin
        create_payable!
      rescue => e
        errors.add(:base, "Cannot approve PO without payable: #{e.message}")
        throw(:abort)
      end
    end
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
  
  def must_have_payable_when_approved
    if payable.blank?
      errors.add(:base, "Payable record must exist for approved purchase orders")
    end
  end
  
  def cannot_cancel_if_paid
    if payable.present? && payable.status == 'paid'
      errors.add(:base, "Cannot cancel a purchase order that has been paid")
    end
  end
end