class VendorInvoiceItem < ApplicationRecord
  belongs_to :vendor_invoice
  belongs_to :part, optional: true
  belongs_to :purchase_order_item, optional: true
  
  # Validations
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :unit_price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  
  # Callbacks
  before_save :calculate_total_price
  after_save :update_part_stock
  after_save :update_vendor_invoice_total
  
  def calculate_total_price
    self.total_price = quantity * unit_price
  end
  
  def update_part_stock
    return unless part.present?
    
    # Update stock and cost price for the part
    part.update_from_vendor_invoice(quantity, unit_price, vendor_invoice)
  end
  
  def update_vendor_invoice_total
    vendor_invoice.update_amount_from_items
  end
  
  # Find corresponding purchase order item if available
  def find_corresponding_po_item
    return nil unless part.present? && vendor_invoice.purchase_order.present?
    
    vendor_invoice.purchase_order.purchase_order_items.find_by(part_id: part.id)
  end
end