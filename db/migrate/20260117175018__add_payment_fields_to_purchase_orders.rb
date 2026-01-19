# db/migrate/20250118010000_add_payment_fields_to_purchase_orders.rb
class AddPaymentFieldsToPurchaseOrders < ActiveRecord::Migration[8.1]
  def change
    # Add payment fields
    add_column :purchase_orders, :payment_method, :string
    add_column :purchase_orders, :payment_reference, :string
    add_column :purchase_orders, :payment_status, :string, default: 'unpaid'
    add_column :purchase_orders, :paid_at, :datetime
    add_column :purchase_orders, :payment_notes, :text
    
    # Add workflow timestamps
    add_column :purchase_orders, :ordered_at, :datetime
    add_column :purchase_orders, :received_at, :datetime
    
    # Add rejection tracking
    add_column :purchase_orders, :rejected_by_id, :bigint
    add_column :purchase_orders, :rejection_reason, :text
    add_column :purchase_orders, :rejected_at, :datetime
    
    add_index :purchase_orders, :payment_status
    add_index :purchase_orders, :payment_reference
  end
end