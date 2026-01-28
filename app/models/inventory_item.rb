# app/models/inventory_item.rb
class InventoryItem < ApplicationRecord
  self.table_name = 'parts'  # Use existing parts table
  
  # Stock management
  def can_fulfill?(quantity)
    current_stock >= quantity
  end
  
  def reserve_stock(quantity, reference)
    # Create inventory transaction
    InventoryTransaction.create!(
      inventory_item: self,
      quantity: quantity,
      transaction_type: 'reservation',
      reference: reference,
      notes: "Reserved for #{reference.class.name} #{reference.id}"
    )
    update!(current_stock: current_stock - quantity)
  end
  
  def release_stock(quantity, reference)
    # Create inventory transaction
    InventoryTransaction.create!(
      inventory_item: self,
      quantity: quantity,
      transaction_type: 'release',
      reference: reference,
      notes: "Released from #{reference.class.name} #{reference.id}"
    )
    update!(current_stock: current_stock + quantity)
  end
  
  def consume_stock(quantity, reference)
    # Create inventory transaction
    InventoryTransaction.create!(
      inventory_item: self,
      quantity: quantity,
      transaction_type: 'consumption',
      reference: reference,
      notes: "Consumed for #{reference.class.name} #{reference.id}"
    )
    update!(current_stock: current_stock - quantity)
  end
  
  # Low stock alerts
  def low_stock?
    current_stock <= reorder_point
  end
  
  def needs_reorder?
    current_stock <= minimum_stock
  end
end