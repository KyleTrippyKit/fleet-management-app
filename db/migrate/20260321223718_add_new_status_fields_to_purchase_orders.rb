class AddNewStatusFieldsToPurchaseOrders < ActiveRecord::Migration[8.1]
  def change
    # Only add columns that don't exist yet
    add_column :purchase_orders, :sent_at, :datetime unless column_exists?(:purchase_orders, :sent_at)
    add_column :purchase_orders, :stock_updated_at, :datetime unless column_exists?(:purchase_orders, :stock_updated_at)
    
    # received_at and ordered_at already exist - no need to add them
  end
end