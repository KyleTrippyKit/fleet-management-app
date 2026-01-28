class ChangeVmcOttStatusToStringInPurchaseOrders < ActiveRecord::Migration[8.1]
  def change
    change_column :purchase_orders, :vmcott_status, :string, default: 'pending_internal_work'
  end
end