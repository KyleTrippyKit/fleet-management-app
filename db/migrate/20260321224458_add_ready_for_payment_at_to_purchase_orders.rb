class AddReadyForPaymentAtToPurchaseOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :purchase_orders, :ready_for_payment_at, :datetime
  end
end
