class AddAcceptanceStatusToPurchaseOrders < ActiveRecord::Migration[6.0]
  def change
    add_column :purchase_orders, :acceptance_status, :integer, default: 0
  end
end