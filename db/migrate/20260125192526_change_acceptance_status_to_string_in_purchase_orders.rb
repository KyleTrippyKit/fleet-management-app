class ChangeAcceptanceStatusToStringInPurchaseOrders < ActiveRecord::Migration[8.1]
  def change
    change_column :purchase_orders, :acceptance_status, :string, default: 'pending_acceptance'
  end
end