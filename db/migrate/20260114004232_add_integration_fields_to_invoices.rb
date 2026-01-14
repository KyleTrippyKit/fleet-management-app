# db/migrate/20260114000001_add_integration_fields_to_invoices.rb
class AddIntegrationFieldsToInvoices < ActiveRecord::Migration[8.1]
  def up
    # Only add columns that don't exist
    unless column_exists?(:invoices, :quickbooks_id)
      add_column :invoices, :quickbooks_id, :string
      add_index :invoices, :quickbooks_id
    end
    
    unless column_exists?(:invoices, :purchase_order_id)
      add_column :invoices, :purchase_order_id, :integer
      add_index :invoices, :purchase_order_id
    end
    
    unless column_exists?(:invoices, :pos_transaction_id)
      add_column :invoices, :pos_transaction_id, :integer
      add_index :invoices, :pos_transaction_id
    end
    
    # These columns already exist in your schema, so don't add them:
    # - category (already exists)
    # - paid_at (already exists)
    # - paid_by_id (already exists)
    # - received_at (already exists)
    # - received_by_id (already exists)
    # - created_by_id (already exists)
    # - disputed_at (already exists)
    # - disputed_by_id (already exists)
  end

  def down
    # Remove columns if they exist
    if column_exists?(:invoices, :quickbooks_id)
      remove_column :invoices, :quickbooks_id
    end
    
    if column_exists?(:invoices, :purchase_order_id)
      remove_column :invoices, :purchase_order_id
    end
    
    if column_exists?(:invoices, :pos_transaction_id)
      remove_column :invoices, :pos_transaction_id
    end
  end
end