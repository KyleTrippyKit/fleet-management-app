# frozen_string_literal: true

class VendorRfq < ApplicationRecord
  STATUSES = %w[draft sent closed awarded].freeze

  # Associations
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :processing_agency, class_name: "Agency", optional: true

  has_many :vendor_rfq_items, dependent: :destroy
  has_many :vendor_quotations, dependent: :destroy

  belongs_to :awarded_vendor_quotation,
             class_name: "VendorQuotation",
             optional: true

  accepts_nested_attributes_for :vendor_rfq_items, allow_destroy: true

  # Validations
  validates :rfq_number, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  # If you ever had null statuses in existing data, switch to:
  # validates :status, inclusion: { in: STATUSES }, allow_nil: true

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :open,   -> { where(status: %w[draft sent]) }

  # Status helpers
  def sent?    = status == "sent"
  def draft?   = status == "draft"
  def awarded? = status == "awarded"
  def closed?  = status == "closed"

  def locked?
    awarded? || closed?
  end

  # Cheapest quotation helper
  def cheapest_vendor_response
    quotes = vendor_quotations.includes(:supplier, :vendor_quotation_lines).to_a
    return nil if quotes.empty?
    quotes.min_by { |q| [q.total_amount.to_d, q.created_at || Time.at(0)] }
  end

  # ✅ Award an RFQ to a quotation (Accept 1, Reject others, Create PO, Lock RFQ)
  def award_to!(quotation:, user:)
    raise ArgumentError, "Quotation must belong to this RFQ" unless quotation.vendor_rfq_id == id
    raise StandardError, "RFQ is locked" if locked?
    raise StandardError, "RFQ already awarded" if awarded_vendor_quotation_id.present?

    ActiveRecord::Base.transaction do
      # Accept chosen quotation
      quotation.update!(status: "accepted")

      # Reject all others
      vendor_quotations.where.not(id: quotation.id).update_all(status: "rejected", updated_at: Time.current)

      # Create Purchase Order
      po = PurchaseOrder.create!(
        vendor: quotation.supplier&.name || "Unknown Supplier",
        supplier_id: quotation.supplier_id,
        created_by: user,
        status: "draft",
        payment_status: "unpaid",
        acceptance_status: "pending_acceptance",
        notes: "Auto-created from Vendor RFQ #{rfq_number} / Quotation ##{quotation.id}"
      )

      quotation.vendor_quotation_lines.find_each do |line|
        po.purchase_order_items.create!(
          part_id: line.try(:part_id),
          description: line.description.presence || line.try(:part)&.name || "Line Item",
          quantity: line.quantity || 1,
          unit_price: line.unit_price || 0,
          notes: line.try(:notes)
        )
      end

      po.recalculate_amount!

      # Link quotation -> PO
      quotation.update!(purchase_order_id: po.id)

      # Optional: create vendor invoice draft record
      if defined?(VendorInvoice)
        VendorInvoice.create!(
          purchase_order_id: po.id,
          supplier_id: po.supplier_id,
          status: "draft",
          invoice_date: Date.current,
          notes: "Awaiting vendor invoice upload (PDF/scan/email)."
        )
      end

      # Lock RFQ
      update!(
        status: "awarded",
        awarded_vendor_quotation_id: quotation.id,
        awarded_at: Time.current
      )

      po
    end
  end
end
