# db/migrate/20260114000000_fix_add_integration_columns_to_invoices.rb
class FixAddIntegrationColumnsToInvoices < ActiveRecord::Migration[7.0]
  def change
    # Only add columns that don't exist
    add_column :invoices, :quickbooks_id, :string unless column_exists?(:invoices, :quickbooks_id)
    add_column :invoices, :purchase_order_id, :integer unless column_exists?(:invoices, :purchase_order_id)
    
    # Don't add category if it already exists
    unless column_exists?(:invoices, :category)
      add_column :invoices, :category, :string, default: 'maintenance'
    end
    
    # Add user reference columns
    add_column :invoices, :paid_at, :datetime unless column_exists?(:invoices, :paid_at)
    add_column :invoices, :paid_by_id, :integer unless column_exists?(:invoices, :paid_by_id)
    add_column :invoices, :received_at, :datetime unless column_exists?(:invoices, :received_at)
    add_column :invoices, :received_by_id, :integer unless column_exists?(:invoices, :received_by_id)
    add_column :invoices, :created_by_id, :integer unless column_exists?(:invoices, :created_by_id)
    
    # Add indexes
    add_index :invoices, :quickbooks_id if column_exists?(:invoices, :quickbooks_id) && !index_exists?(:invoices, :quickbooks_id)
    add_index :invoices, :purchase_order_id if column_exists?(:invoices, :purchase_order_id) && !index_exists?(:invoices, :purchase_order_id)
    add_index :invoices, :category if column_exists?(:invoices, :category) && !index_exists?(:invoices, :category)
  end
end