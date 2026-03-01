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

  # ============================================
  # NEW METHODS FOR QUOTATION COMPARISON AND AWARDING
  # ============================================

  # Generate a comprehensive quotation comparison for all items
  def quotation_comparison
    result = {}
    vendor_rfq_items.each do |item|
      part = item.part
      
      # Skip if no part is associated
      next unless part

      # Get all quotations that include this part
      quotes = vendor_quotations
        .joins(:vendor_quotation_lines)
        .where(vendor_quotation_lines: { part_id: part.id })
        .select('vendor_quotations.*, vendor_quotation_lines.unit_price, vendor_quotation_lines.quantity')
        .order('vendor_quotation_lines.unit_price ASC')

      # Find the lowest price quotation for this part
      lowest = quotes.min_by(&:unit_price)

      # Find the most frequent supplier for this part based on purchase history
      most_frequent = PurchaseOrder.joins(:purchase_order_items)
                                    .where(purchase_order_items: { part_id: part.id })
                                    .group(:vendor)
                                    .count
                                    .max_by { |_, count| count }
                                    &.first

      result[part.id] = {
        part: part,
        quantity: item.quantity,
        quotations: quotes,
        lowest_price: lowest,
        most_frequent_supplier: most_frequent
      }
    end
    result
  end

  # Award the RFQ to a specific quotation (creates purchase order, rejects others)
  def award_to!(quotation, user)
    raise ArgumentError, "RFQ is locked" if locked?
    raise ArgumentError, "RFQ already awarded" if awarded?
    raise ArgumentError, "Quotation does not belong to this RFQ" unless quotation.vendor_rfq_id == id

    ActiveRecord::Base.transaction do
      # Accept the chosen quotation
      quotation.update!(status: 'accepted')

      # Reject all other quotations
      vendor_quotations.where.not(id: quotation.id).update_all(status: 'rejected')

      # Create Purchase Order
      po = PurchaseOrder.create!(
        vendor: quotation.supplier.name,
        supplier_id: quotation.supplier_id,
        created_by: user,
        status: 'draft',
        payment_status: 'unpaid',
        acceptance_status: 'pending_acceptance',
        notes: "Created from RFQ ##{rfq_number} awarded to #{quotation.supplier.name}"
      )

      # Add items from the quotation to the purchase order
      quotation.vendor_quotation_lines.each do |line|
        po.purchase_order_items.create!(
          part_id: line.part_id,
          description: line.description.presence || line.part&.name || "Line Item",
          quantity: line.quantity,
          unit_price: line.unit_price,
          total_price: line.unit_price * line.quantity
        )
      end
      
      # Recalculate the total amount
      po.recalculate_amount!

      # Link quotation to the purchase order
      quotation.update!(purchase_order_id: po.id)

      # Optional: Create a draft vendor invoice if the model exists
      if defined?(VendorInvoice)
        VendorInvoice.create!(
          purchase_order_id: po.id,
          supplier_id: po.supplier_id,
          status: 'draft',
          invoice_date: Date.current,
          notes: "Awaiting vendor invoice upload from #{quotation.supplier.name}"
        )
      end

      # Lock the RFQ as awarded
      update!(
        status: 'awarded',
        awarded_vendor_quotation_id: quotation.id,
        awarded_at: Time.current
      )

      po
    end
  end

  # ✅ Award an RFQ to a quotation (Accept 1, Reject others, Create PO, Lock RFQ)
  # This is an alias for backward compatibility
  def award_to!(quotation:, user:)
    award_to!(quotation, user)
  end
end