class AddVmcottStatusToPurchaseOrders < ActiveRecord::Migration[6.0]
  def change
    add_column :purchase_orders, :vmcott_status, :integer, default: 0, null: false
  end
end
