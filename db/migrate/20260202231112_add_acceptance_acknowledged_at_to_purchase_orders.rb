# db/migrate/YYYYMMDDHHMMSS_add_acceptance_acknowledged_at_to_purchase_orders.rb
class AddAcceptanceAcknowledgedAtToPurchaseOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :purchase_orders, :acceptance_acknowledged_at, :datetime
    add_index :purchase_orders, :acceptance_acknowledged_at
  end
end