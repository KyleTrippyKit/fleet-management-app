class FixPartsRequestsForeignKeys < ActiveRecord::Migration[8.1]
  def change
    # Remove the old incorrect foreign keys if they exist
    remove_foreign_key :parts_requests, column: :purchase_order_id_id if foreign_key_exists?(:parts_requests, column: :purchase_order_id_id)
    remove_foreign_key :parts_requests, column: :vendor_invoice_id_id if foreign_key_exists?(:parts_requests, column: :vendor_invoice_id_id)
    
    # Rename the incorrectly named columns
    rename_column :parts_requests, :purchase_order_id_id, :purchase_order_id
    rename_column :parts_requests, :vendor_invoice_id_id, :vendor_invoice_id
    
    # Add proper foreign keys
    add_foreign_key :parts_requests, :purchase_orders
    add_foreign_key :parts_requests, :vendor_invoices
    
    # Add indexes for performance
    add_index :parts_requests, :purchase_order_id unless index_exists?(:parts_requests, :purchase_order_id)
    add_index :parts_requests, :vendor_invoice_id unless index_exists?(:parts_requests, :vendor_invoice_id)
  end
  
  def down
    # Reverse the changes if needed
    rename_column :parts_requests, :purchase_order_id, :purchase_order_id_id
    rename_column :parts_requests, :vendor_invoice_id, :vendor_invoice_id_id
    
    remove_foreign_key :parts_requests, :purchase_orders if foreign_key_exists?(:parts_requests, :purchase_orders)
    remove_foreign_key :parts_requests, :vendor_invoices if foreign_key_exists?(:parts_requests, :vendor_invoices)
    
    remove_index :parts_requests, :purchase_order_id if index_exists?(:parts_requests, :purchase_order_id)
    remove_index :parts_requests, :vendor_invoice_id if index_exists?(:parts_requests, :vendor_invoice_id)
  end
end