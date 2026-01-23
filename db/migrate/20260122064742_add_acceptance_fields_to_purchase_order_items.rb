# db/migrate/20250120_add_acceptance_fields_to_purchase_order_items.rb
class AddAcceptanceFieldsToPurchaseOrderItems < ActiveRecord::Migration[8.1]
  def change
    add_column :purchase_order_items, :is_accepted, :boolean, default: true
    add_column :purchase_order_items, :rejection_reason, :text
    
    # Add index for querying accepted/rejected items
    add_index :purchase_order_items, :is_accepted
  end
end