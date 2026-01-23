# db/migrate/20250120_add_aging_fields_to_invoices.rb
class AddAgingFieldsToInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :aging_category, :string  # current, 30_days, 60_days, 90_days, over_90
    add_column :invoices, :days_overdue, :integer, default: 0
    add_column :invoices, :aging_bucket, :string  # for grouping in reports
    
    # Add indexes for faster aging queries
    add_index :invoices, :aging_category
    add_index :invoices, :days_overdue
    add_index :invoices, :aging_bucket
  end
end