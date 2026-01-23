# db/migrate/20250120_add_quotation_id_to_purchase_orders.rb
class AddQuotationIdToPurchaseOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :purchase_orders, :quotation_id, :bigint
    add_index :purchase_orders, :quotation_id
    
    # Add foreign key constraint
    add_foreign_key :purchase_orders, :quotations
  end
end