class AddPaymentTrackingToPurchaseOrders < ActiveRecord::Migration[8.1]
  def change
    # Check and add each column only if it doesn't exist
    add_column :purchase_orders, :payment_initiated_at, :datetime, if_not_exists: true
    add_column :purchase_orders, :payment_authorized_at, :datetime, if_not_exists: true
    add_column :purchase_orders, :payment_failed_at, :datetime, if_not_exists: true
    # Skip payment_notes since it exists
    add_column :purchase_orders, :compliance_checked, :boolean, default: false, if_not_exists: true
    add_column :purchase_orders, :rails_code, :string, if_not_exists: true
  end
end