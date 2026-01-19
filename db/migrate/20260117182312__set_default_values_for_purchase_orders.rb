# db/migrate/20250118020000_set_default_values_for_purchase_orders.rb
class SetDefaultValuesForPurchaseOrders < ActiveRecord::Migration[8.1]
  def up
    # Set default status for nil values
    PurchaseOrder.where(status: nil).update_all(status: 'draft')
    
    # Set default payment_status for nil values
    PurchaseOrder.where(payment_status: nil).update_all(payment_status: 'unpaid')
  end

  def down
    # This migration is reversible but data changes are permanent
    # We can't easily revert to nil
  end
end