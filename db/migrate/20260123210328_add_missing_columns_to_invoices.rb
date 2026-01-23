# db/migrate/20260123210328_add_missing_columns_to_invoices.rb
class AddMissingColumnsToInvoices < ActiveRecord::Migration[8.1]  # Fix Rails version
  def change
    # Only add columns that don't exist
    unless column_exists?(:invoices, :priority)
      add_column :invoices, :priority, :string, default: 'medium'
    end
    
    # aging_bucket already exists from migration 20260122064855
    # We'll just add the default value if needed
    change_column_default :invoices, :aging_bucket, 'current' if column_exists?(:invoices, :aging_bucket)
    
    unless column_exists?(:invoices, :sync_status)
      add_column :invoices, :sync_status, :string, default: 'pending'
    end
    
    unless column_exists?(:invoices, :payment_terms)
      add_column :invoices, :payment_terms, :string, default: 'net_30'
    end
    
    # Add indexes if they don't exist
    add_index :invoices, :priority unless index_exists?(:invoices, :priority)
    add_index :invoices, :aging_bucket unless index_exists?(:invoices, :aging_bucket)
    add_index :invoices, :sync_status unless index_exists?(:invoices, :sync_status)
  end
end