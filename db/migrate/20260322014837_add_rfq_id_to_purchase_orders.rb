class AddRfqIdToPurchaseOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :purchase_orders, :rfq_id, :integer
  end
end
