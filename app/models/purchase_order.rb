# app/models/purchase_order.rb
class PurchaseOrder < ApplicationRecord
  # -------------------------
  # Associations
  # -------------------------
  belongs_to :vehicle, optional: true
  belongs_to :created_by, class_name: 'User'
  belongs_to :approved_by, class_name: 'User', optional: true
  belongs_to :rejected_by, class_name: 'User', optional: true
  belongs_to :payment_authorized_by, class_name: 'User', optional: true
  belongs_to :quotation, optional: true # Link to quotation
  belongs_to :supplier, optional: true  # Link to supplier model

  has_one :payable, dependent: :destroy

  has_many :purchase_order_items, dependent: :destroy
  has_many :invoices, dependent: :nullify
  has_many :payment_histories, as: :payment_transaction
  has_many :payment_audits, dependent: :destroy
  has_many :acceptance_audits, class_name: 'PurchaseOrderAcceptanceAudit', dependent: :destroy
  has_many :vendor_invoices

  # Link to internal POS (VMCOTT internal work orders)
  has_many :internal_pos, dependent: :nullify

  # Accept nested attributes for line items
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
    partially_accepted: 'partially_accepted',
    fully_accepted: 'fully_accepted',
    partially_rejected: 'partially_rejected',
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
  # RFQ WORKFLOW METHODS
  # -------------------------

  def accepted_items_total
    purchase_order_items.where(is_accepted: true).sum(&:total_price)
  end

  def rejected_items_total
    purchase_order_items.where(is_accepted: false).sum(&:total_price)
  end

  def recalculate_amount!
    update(amount: accepted_items_total)
  end

  # Status helpers
  def can_create_internal_pos?
    status == 'approved' && acceptance_status == 'fully_accepted'
  end

  # Quotation to PO Workflow Methods
  def self.create_from_quotation(quotation, accepted_items_data, user)
    ActiveRecord::Base.transaction do
      po = create!(
        quotation_id: quotation.id,
        vehicle_id: quotation.vehicle_id,
        vendor: quotation.vendor,
        amount: calculate_total_from_accepted_items(quotation, accepted_items_data),
        created_by: user,
        status: 'draft',
        acceptance_status: 'partially_accepted',
        notes: "Created from Quotation #{quotation.quote_number}"
      )

      accepted_items_data.each do |item_data|
        if item_data[:accepted] && item_data[:item_type] == 'job'
          job = quotation.quotation_jobs.find(item_data[:item_id])
          po.purchase_order_items.create!(
            description: job.name,
            quantity: 1,
            unit_price: job.total_labor_cost,
            notes: "Job: #{job.description}"
          )
        elsif item_data[:accepted] && item_data[:item_type] == 'part'
          part_item = quotation.quotation_job_parts.find(item_data[:item_id])
          po.purchase_order_items.create!(
            part_id: part_item.part_id,
            description: part_item.part&.name || "Part from job",
            quantity: part_item.quantity,
            unit_price: part_item.unit_price,
            notes: part_item.part&.description
          )
        end
      end

      po.update_acceptance_status
      po
    end
  end

  def self.calculate_total_from_accepted_items(quotation, accepted_items_data)
    total = 0

    accepted_items_data.each do |item_data|
      if item_data[:accepted] && item_data[:item_type] == 'job'
        job = quotation.quotation_jobs.find(item_data[:item_id])
        total += job.total_labor_cost
      elsif item_data[:accepted] && item_data[:item_type] == 'part'
        part_item = quotation.quotation_job_parts.find(item_data[:item_id])
        total += part_item.total_price
      end
    end

    total
  end

  def self.create_purchase_order_from_accepted_items(quotation, accepted_items, user)
    accepted_items_data = accepted_items.map do |item|
      {
        accepted: true,
        item_type: item[:item_type],
        item_id: item[:item_id]
      }
    end

    create_from_quotation(quotation, accepted_items_data, user)
  end

  # -------------------------
  # VMCOTT Internal POS Creation
  # -------------------------
  def create_internal_pos(assigned_to_id, estimated_completion_date, notes, user)
    return unless defined?(InternalPos)

    ActiveRecord::Base.transaction do
      internal_po = InternalPos.create!(
        purchase_order_id: id,
        assigned_to_id: assigned_to_id,
        estimated_completion_date: estimated_completion_date,
        status: 'pending',
        priority: 'medium',
        notes: notes,
        created_by: user
      )

      update!(vmcott_status: 'work_in_progress')

      create_vmcott_audit(:internal_pos_created, user, {
        assigned_to_id: assigned_to_id,
        estimated_completion_date: estimated_completion_date,
        internal_pos_id: internal_po.id
      })

      internal_po
    end
  end

  # -------------------------
  # VMCOTT Status Management
  # -------------------------
  def mark_work_in_progress!(user)
    update!(vmcott_status: 'work_in_progress')
    create_vmcott_audit(:work_started, user)
  end

  def mark_internal_work_completed!(user)
    update!(vmcott_status: 'internal_work_completed')
    create_vmcott_audit(:work_completed, user)
  end

  def mark_ready_for_delivery!(user)
    update!(vmcott_status: 'ready_for_delivery')
    create_vmcott_audit(:ready_for_delivery, user)
  end

  def mark_delivered!(user)
    update!(vmcott_status: 'delivered')
    create_vmcott_audit(:delivered, user)
  end

  # -------------------------
  # Acceptance Workflow Methods
  # -------------------------
  def update_acceptance_status
    total_items = purchase_order_items.count
    accepted_items = purchase_order_items.accepted.count
    rejected_items = purchase_order_items.rejected.count

    if total_items == 0
      self.acceptance_status = 'pending_acceptance'
    elsif accepted_items == total_items
      self.acceptance_status = 'fully_accepted'
    elsif rejected_items == total_items
      self.acceptance_status = 'fully_rejected'
    elsif accepted_items > 0
      self.acceptance_status = 'partially_accepted'
    else
      self.acceptance_status = 'pending_acceptance'
    end

    save if changed?

    notify_vendor_of_acceptance if fully_accepted? && saved_change_to_acceptance_status?
  end

  def rejected_items_with_reasons
    purchase_order_items.rejected.map do |item|
      {
        description: item.description,
        quantity: item.quantity,
        unit_price: item.unit_price,
        rejection_reason: item.rejection_reason,
        total: item.total_price
      }
    end
  end

  def accept_item(item_id, user = nil)
    item = purchase_order_items.find(item_id)
    item.update!(
      is_accepted: true,
      rejection_reason: nil
    )
    update_acceptance_status
    log_acceptance_audit(:item_accepted, item, user)
  end

  def reject_item(item_id, reason, user = nil)
    item = purchase_order_items.find(item_id)
    item.update!(
      is_accepted: false,
      rejection_reason: reason
    )
    update_acceptance_status
    log_acceptance_audit(:item_rejected, item, user, reason)
  end

  def notify_vendor_of_acceptance
    return unless quotation.present?

    PurchaseOrderMailer.acceptance_notification(self).deliver_later if defined?(PurchaseOrderMailer)
    quotation.update(accepted_at: Time.current) if fully_accepted?

    if quotation.processing_agency.present?
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
  # State machine methods
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
    update!(
      status: 'cancelled',
      notes: [notes, "Cancelled on #{Date.today}: #{reason}"].compact.join("\n")
    )
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
  def initiate_trinidad_card_payment!(user, card_details, billing_address)
    return false unless can_initiate_payment?

    payment_result =
      if Rails.env.production? && ENV['USE_REAL_PAYMENTS'] == 'true'
        TrinidadPaymentGateway.process(
          amount: amount,
          card_details: card_details,
          billing_address: billing_address,
          reference: po_number
        )
      else
        MockPaymentService.process_payment(
          purchase_order: self,
          user: user,
          card_details: card_details,
          billing_address: billing_address
        )
      end

    if payment_result.success?
      method = (card_details[:card_type] == 'debit' ? 'trinidad_debit_card' : 'trinidad_credit_card')

      update!(
        payment_method: card_details[:card_type] == 'debit' ? 'trinidad_debit_card' : 'trinidad_credit_card',
        card_type: card_details[:card_brand],
        last_four_digits: card_details[:last_four],
        payment_reference: payment_result.transaction_id,
        billing_address: billing_address,     # jsonb column, keep hash
        payment_status: 'pending',            # ✅ payment_status enum
        payment_initiated_at: Time.current,
        payment_processed_by_id: user.id
      )
      
      PaymentAudit.log(
        self,
        user,
        :initiated,
        {
          amount: amount,
          payment_method: method,
          card_last_four: card_details[:last_four],
          reference: payment_result.transaction_id,
          bank_response: payment_result.bank_response,
          environment: (Rails.env.production? && ENV['USE_REAL_PAYMENTS'] == 'true') ? 'production' : 'development/mock'
        }
      )

      true
    else
      errors.add(:base, "Payment initiation failed: #{payment_result.error_message}")
      false
    end
  end

  def authorize_trinidad_payment!(user)
    return false unless payment_status == 'pending'

    update!(
      payment_status: 'authorized', # ✅ CORRECT: payment_status
      payment_authorized_at: Time.current,
      payment_authorized_by_id: user.id
    )

    PaymentAudit.log(
      self,
      user,
      :authorized,
      {
        authorization_time: Time.current.iso8601,
        authorized_by: user.name
      }
    )

    TrinidadPaymentProcessingJob.perform_later(id) if defined?(TrinidadPaymentProcessingJob)
    true
  end

  def complete_trinidad_payment!
    return false unless payment_status == 'authorized'

    update!(
      payment_status: 'completed', # ✅ Payment is complete
      status: 'paid',              # ✅ Order is paid
      payment_date: Time.current,
      paid_at: Time.current
    )

    payment_histories.update_all(status: 'completed', payment_date: Time.current)

    PaymentAudit.log(
      self,
      nil,
      :completed,
      {
        completion_time: Time.current.iso8601,
        settlement_date: Date.current
      }
    )

    auto_create_invoice_if_paid
    true
  end

  def fail_trinidad_payment!(error_message)
    update!(
      payment_status: 'failed', # ✅ CORRECT: payment_status
      payment_notes: "Payment failed: #{error_message}",
      payment_failed_at: Time.current
    )

    payment_histories.update_all(status: 'failed')

    PaymentAudit.log(
      self,
      nil,
      :failed,
      {
        error: error_message,
        failed_at: Time.current.iso8601
      }
    )
  end

  def mark_as_paid!(reference:, method:, user:, notes: nil, last_four_digits: nil, card_type: nil)
    update!(
      payment_status: 'completed', # ✅ Payment complete
      payment_method: method,
      payment_reference: reference,
      paid_at: Time.current,
      payment_date: Time.current,
      payment_notes: notes,
      last_four_digits: last_four_digits,
      card_type: card_type,
      status: 'paid'              # ✅ Order paid
    )

    PaymentAudit.log(
      self,
      user,
      :completed,
      {
        method: method,
        reference: reference,
        notes: notes,
        marked_by: user.name
      }
    )

    auto_create_invoice_if_paid
  end

  # -------------------------
  # Payment Status Methods
  # -------------------------
  def payment_initiated?
    payment_initiated_at.present?
  end

  def payment_authorized?
    payment_authorized_at.present?
  end

  def payment_failed?
    payment_failed_at.present?
  end

  def payment_initiated!
    update(payment_initiated_at: Time.current)
    log_payment_audit(:initiated) if respond_to?(:log_payment_audit)
  end

  def log_payment_audit(action, metadata = {})
    PaymentAudit.log(self, Current.user || User.system_user, action, metadata)
  end

  # -------------------------
  # Business Logic Methods
  # -------------------------
  def can_initiate_payment?
    status == 'approved' && unpaid? && fully_accepted?
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

  def payment_card_summary
    return unless last_four_digits.present?

    if is_trinidad_payment?
      "Trinidad #{card_type&.upcase} •••• #{last_four_digits}"
    else
      "#{card_type&.upcase} •••• #{last_four_digits}"
    end
  end

  def editable?
    draft? || pending_approval?
  end

  def can_be_paid?
    approved? && unpaid? && fully_accepted?
  end

  def can_be_approved?
    pending_approval?
  end

  def update_amount_from_items
    calculate_amount_from_items
    save if changed?
  end

  def billing_address_hash
    return {} if billing_address.blank?
    JSON.parse(billing_address)
  rescue JSON::ParserError
    {}
  end

  def all_items_accepted?
    fully_accepted?
  end

  def any_items_rejected?
    purchase_order_items.rejected.any?
  end

  def rejected_items
    purchase_order_items.rejected
  end

  def fully_accepted?
    acceptance_status == 'fully_accepted' ||
      (purchase_order_items.count > 0 && purchase_order_items.accepted.count == purchase_order_items.count)
  end

  # VMCOTT status checks
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

    raise "PurchaseOrder #{id} has no agency_id (vehicle missing or vehicle has no agency)" if agency_id.blank?
    raise "PurchaseOrder #{id} has no vendor" if vendor.blank?
    raise "PurchaseOrder #{id} has invalid amount (#{amount.inspect})" if amount.blank? || amount.to_f <= 0

    payable_account = Account.payable_accounts
                             .for_agency(agency_id)
                             .first_or_create!(
                               account_number: '2000',
                               name: 'Accounts Payable',
                               account_type: 'liability',
                               sub_type: 'accounts_payable',
                               agency_id: agency_id
                             )

    Payable.create!(
      purchase_order_id: id,
      vendor_name: vendor,
      agency_id: agency_id,
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
  # Print/PDF methods
  # -------------------------
  def print_data
    {
      po_number: po_number,
      vendor: vendor,
      amount: sprintf('$%.2f', amount),
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
          accepted: item.is_accepted? ? 'Yes' : 'No',
          rejection_reason: item.rejection_reason
        }
      end,
      line_items_total: sprintf('$%.2f', line_items_total),
      accepted_items_total: sprintf('$%.2f', accepted_items_total),
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

   # Called by PurchaseOrderItem callbacks
  def update_total_amount
      total =
        purchase_order_items.sum("COALESCE(quantity,0) * COALESCE(unit_price,0)")
      # choose the correct column name below (amount vs total_amount)
      if self.class.column_names.include?("amount")
        update_column(:amount, total)
      elsif self.class.column_names.include?("total_amount")
        update_column(:total_amount, total)
      end
  end


  def save_as_pdf_to_s3
    return unless Rails.application.config.enable_s3_storage

    pdf_content = to_pdf
    filename = "purchase_order_#{po_number}_#{Time.current.to_i}.pdf"

    s3 = Aws::S3::Resource.new
    bucket = s3.bucket(Rails.application.config.s3_bucket_name)

    obj = bucket.object("purchase_orders/#{filename}")
    obj.put(
      body: pdf_content,
      content_type: 'application/pdf',
      metadata: {
        'po_number' => po_number,
        'vendor' => vendor,
        'amount' => amount.to_s,
        'generated_at' => Time.current.iso8601
      }
    )

    update(pdf_s3_url: obj.public_url)
    obj.public_url
  rescue => e
    Rails.logger.error "Failed to save PDF to S3: #{e.message}"
    nil
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
    when 'partially_accepted' then 'warning'
    when 'fully_rejected' then 'danger'
    when 'partially_rejected' then 'danger'
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
    acceptance_status.humanize.titleize
  end

  def display_vmcott_status
    vmcott_status.humanize.titleize
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

  def line_items_total
    purchase_order_items.sum { |item| item.quantity * item.unit_price }
  end

  def acceptance_summary
    total = purchase_order_items.count
    accepted = purchase_order_items.accepted.count
    rejected = purchase_order_items.rejected.count

    "Accepted: #{accepted}/#{total} • Rejected: #{rejected}/#{total}"
  end

  def internal_work_summary
    return "No internal POS" unless has_internal_pos?

    completed = internal_pos.completed.count
    total = internal_pos.count

    "POS: #{completed}/#{total} completed"
  end

  def has_pdf?
    pdf_s3_url.present?
  end

  def pdf_filename
    "Purchase_Order_#{po_number}.pdf"
  end

  def compliance_checked?
    compliance_checked.present? && compliance_checked
  end

  def trinidad_payment_pending_authorization?
    is_trinidad_payment? && payment_status == 'pending'
  end

  def trinidad_payment_authorized?
    is_trinidad_payment? && payment_status == 'authorized'
  end

  # -------------------------
  # Convenience methods for backward compatibility
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
  # Compliance check
  # -------------------------
  def check_compliance
    TrinidadComplianceChecker.check_compliance(self)
  end

  # -------------------------
  # Validations
  # -------------------------
  validates :po_number, presence: true, uniqueness: true
  validates :vendor, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validates :status, presence: true
  validates :payment_status, presence: true

  # -------------------------
  # Scopes - CORRECTED for schema
  # -------------------------
  scope :recent, -> { order(created_at: :desc) }
  scope :for_agency, ->(agency_id) { joins(:vehicle).where(vehicles: { agency_id: agency_id }) }

  # Acceptance scopes
  scope :awaiting_acceptance, -> { where(acceptance_status: ['pending_acceptance', 'partially_accepted']) }
  scope :fully_accepted, -> { where(acceptance_status: 'fully_accepted') }
  scope :with_rejected_items, -> { where(acceptance_status: ['partially_rejected', 'fully_rejected']) }

  # VMCOTT scopes
  scope :pending_internal_work, -> { where(vmcott_status: 'pending_internal_work') }
  scope :work_in_progress, -> { where(vmcott_status: 'work_in_progress') }
  scope :ready_for_delivery, -> { where(vmcott_status: 'ready_for_delivery') }
  scope :has_internal_pos, -> { where.not(vmcott_status: 'pending_internal_work') }

  # Status scopes (using status column)
  scope :pending_approval, -> { where(status: 'pending_approval') }
  scope :needs_payment, -> { where(status: 'approved', payment_status: 'unpaid') } # ✅ Correct: status AND payment_status
  scope :ordered, -> { where(status: 'ordered') }
  scope :received, -> { where(status: 'received') }

  # Payment status scopes (using payment_status column)
  scope :unpaid, -> { where(payment_status: ['unpaid', 'failed']) } # ✅ Correct: payment_status
  scope :paid, -> { where(payment_status: 'completed') } # ✅ Correct: payment_status
  scope :payment_pending, -> { where(payment_status: ['pending', 'processing', 'authorized']) } # ✅ Correct: payment_status

  # Active purchase orders (not cancelled or fully paid)
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
  # Callbacks
  # -------------------------
  before_validation :generate_po_number, on: :create
  before_validation :set_default_statuses, on: :create
  before_validation :calculate_amount_from_items, if: -> { purchase_order_items.present? }
  before_save :link_supplier

  after_update :auto_create_invoice_if_paid
  after_update :create_payment_audit_trail, if: :saved_change_to_payment_status?
  after_save :update_acceptance_status, if: :saved_change_to_purchase_order_items?

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
    calculated_amount = purchase_order_items.sum { |item| item.quantity * item.unit_price }
    self.amount = calculated_amount if calculated_amount.to_f > 0
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
    PaymentAudit.create_audit_trail(self)
  end

  def saved_change_to_purchase_order_items?
    purchase_order_items.any?(&:saved_changes?)
  end

  def log_acceptance_audit(action, item, user = nil, reason = nil)
    metadata = {
      item_id: item.id,
      item_description: item.description,
      quantity: item.quantity,
      unit_price: item.unit_price
    }
    metadata[:rejection_reason] = reason if reason

    PurchaseOrderAcceptanceAudit.create!(
      purchase_order: self,
      user: user,
      action: action,
      metadata: metadata
    )
  end

  def create_vmcott_audit(action, user = nil, metadata = {})
    return unless defined?(VMCOTTAudit)

    VMCOTTAudit.create!(
      purchase_order: self,
      user: user,
      action: action,
      metadata: metadata
    )
  end
end