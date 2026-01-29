# app/models/purchase_order_item.rb
class PurchaseOrderItem < ApplicationRecord
  belongs_to :purchase_order
  belongs_to :part, optional: true
  has_many :vendor_invoice_items, dependent: :nullify
  
  validates :description, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :unit_price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_price, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Add acceptance fields
  attribute :is_accepted, :boolean, default: true
  
  # Add scopes for acceptance
  scope :accepted, -> { where(is_accepted: true) }
  scope :rejected, -> { where(is_accepted: false) }
  scope :pending_acceptance, -> { where(is_accepted: nil) }
  
  # NEW: Scope for items with remaining quantity to invoice
  scope :with_remaining_quantity, -> {
    joins("LEFT JOIN vendor_invoice_items ON vendor_invoice_items.purchase_order_item_id = purchase_order_items.id")
      .group("purchase_order_items.id")
      .select("purchase_order_items.*, purchase_order_items.quantity - COALESCE(SUM(vendor_invoice_items.quantity), 0) as remaining_quantity")
      .having("purchase_order_items.quantity - COALESCE(SUM(vendor_invoice_items.quantity), 0) > 0")
  }
  
  # NEW: Scope for fully invoiced items
  scope :fully_invoiced, -> {
    joins("LEFT JOIN vendor_invoice_items ON vendor_invoice_items.purchase_order_item_id = purchase_order_items.id")
      .group("purchase_order_items.id")
      .having("COALESCE(SUM(vendor_invoice_items.quantity), 0) >= purchase_order_items.quantity")
  }

  before_save :calculate_total
  after_save :update_purchase_order_total
  after_destroy :update_purchase_order_total
  
  # NEW: Validate that quantity doesn't exceed available stock when part is consumable
  validate :check_stock_availability, if: -> { part.present? && part.is_consumable? && purchase_order&.pending? }

  def calculate_total
    self.total_price = quantity * unit_price if quantity && unit_price
  end
  
  def update_purchase_order_total
    purchase_order.update_total_amount if purchase_order.persisted?
  end
  
  # NEW: Check if there's enough stock before creating PO item
  def check_stock_availability
    if quantity > part.current_stock
      errors.add(:quantity, "exceeds available stock. Only #{part.current_stock} available.")
    end
  end

  # NEW: Calculate invoiced quantity
  def invoiced_quantity
    vendor_invoice_items.sum(:quantity)
  end
  
  # NEW: Calculate remaining quantity to be invoiced
  def remaining_quantity
    quantity - invoiced_quantity
  end
  
  # NEW: Check if item is fully invoiced
  def fully_invoiced?
    invoiced_quantity >= quantity
  end
  
  # NEW: Check if item has been partially invoiced
  def partially_invoiced?
    invoiced_quantity > 0 && invoiced_quantity < quantity
  end
  
  # NEW: Get invoicing status
  def invoicing_status
    if fully_invoiced?
      'fully_invoiced'
    elsif partially_invoiced?
      'partially_invoiced'
    else
      'not_invoiced'
    end
  end
  
  # NEW: Invoicing status badge class
  def invoicing_badge_class
    case invoicing_status
    when 'fully_invoiced'
      'badge bg-success'
    when 'partially_invoiced'
      'badge bg-warning text-dark'
    else
      'badge bg-secondary'
    end
  end
  
  # NEW: Invoicing status text
  def invoicing_text
    case invoicing_status
    when 'fully_invoiced'
      '✓ Fully Invoiced'
    when 'partially_invoiced'
      "⏳ Partially Invoiced (#{invoiced_quantity}/#{quantity})"
    else
      'Not Invoiced'
    end
  end
  
  # NEW: Get all vendor invoices for this item
  def vendor_invoices
    vendor_invoice_items.includes(:vendor_invoice).map(&:vendor_invoice).uniq
  end
  
  # NEW: Update stock when PO is received/completed
  def update_stock_on_receipt(notes = nil)
    return unless part.present?
    
    # Only update stock if PO is completed/received
    if purchase_order.completed? || purchase_order.received?
      part.receive_from_purchase(
        quantity,
        purchase_order,
        notes || "Received via PO #{purchase_order.po_number}"
      )
      true
    else
      false
    end
  end
  
  # NEW: Get part cost details
  def part_cost_details
    return {} unless part.present?
    
    {
      part_name: part.name,
      part_number: part.part_number,
      current_stock: part.current_stock,
      minimum_stock: part.minimum_stock,
      reorder_point: part.reorder_point,
      cost_price: part.cost_price,
      selling_price: part.selling_price,
      markup_percentage: part.standard_markup_percentage
    }
  end
  
  # NEW: Calculate profit margin if part has cost price
  def profit_margin
    return nil unless part.present? && part.cost_price.present? && unit_price.present?
    
    if part.cost_price > 0
      ((unit_price - part.cost_price) / part.cost_price * 100).round(2)
    else
      0
    end
  end
  
  # NEW: Calculate profit amount
  def profit_amount
    return nil unless part.present? && part.cost_price.present? && unit_price.present?
    
    (unit_price - part.cost_price) * quantity
  end
  
  # NEW: Check if this item corresponds to a quotation item
  def quotation_item
    # Assuming you have a way to trace back to quotation items
    # This might need adjustment based on your specific implementation
    QuotationLineItem.find_by(
      description: description,
      part_id: part_id
    )
  end
  
  # NEW: Create a vendor invoice item from this PO item
  def create_vendor_invoice_item(vendor_invoice, quantity_to_invoice = nil)
    return nil unless part.present?
    
    quantity_to_invoice ||= remaining_quantity
    return nil if quantity_to_invoice <= 0
    
    vendor_invoice.vendor_invoice_items.create!(
      part: part,
      purchase_order_item: self,
      quantity: quantity_to_invoice,
      unit_price: unit_price,
      description: description
    )
  end
  
  def unit_price_formatted
    sprintf('%.2f', unit_price)
  end
  
  def total_price_formatted
    sprintf('%.2f', total_price)
  end
  
  # Get acceptance status for display
  def acceptance_status
    if is_accepted.nil?
      'pending'
    elsif is_accepted
      'accepted'
    else
      'rejected'
    end
  end
  
  # Get acceptance badge class for UI
  def acceptance_badge_class
    case acceptance_status
    when 'accepted'
      'badge bg-success'
    when 'rejected'
      'badge bg-danger'
    when 'pending'
      'badge bg-warning text-dark'
    else
      'badge bg-secondary'
    end
  end
  
  # Get acceptance text for display
  def acceptance_text
    case acceptance_status
    when 'accepted'
      '✓ Accepted'
    when 'rejected'
      '✗ Rejected'
    when 'pending'
      '⏳ Pending'
    else
      'Not Reviewed'
    end
  end
  
  # NEW: Combined status badge for acceptance and invoicing
  def combined_status_badge
    if acceptance_status == 'rejected'
      acceptance_badge_class
    elsif invoicing_status == 'fully_invoiced'
      'badge bg-success'
    elsif invoicing_status == 'partially_invoiced'
      'badge bg-info'
    else
      acceptance_badge_class
    end
  end
  
  # NEW: Combined status text
  def combined_status_text
    if acceptance_status == 'rejected'
      acceptance_text
    elsif invoicing_status == 'fully_invoiced'
      '✓ Fully Invoiced'
    elsif invoicing_status == 'partially_invoiced'
      invoicing_text
    else
      acceptance_text
    end
  end
  
  # NEW: Serialize for API/JSON responses
  def as_json(options = {})
    super(options).merge({
      part_name: part&.name,
      part_number: part&.part_number,
      invoiced_quantity: invoiced_quantity,
      remaining_quantity: remaining_quantity,
      fully_invoiced: fully_invoiced?,
      partially_invoiced: partially_invoiced?,
      invoicing_status: invoicing_status,
      invoicing_text: invoicing_text,
      acceptance_status: acceptance_status,
      acceptance_text: acceptance_text,
      combined_status_text: combined_status_text,
      vendor_invoice_count: vendor_invoice_items.count,
      can_create_invoice: remaining_quantity > 0 && acceptance_status == 'accepted'
    })
  end
end