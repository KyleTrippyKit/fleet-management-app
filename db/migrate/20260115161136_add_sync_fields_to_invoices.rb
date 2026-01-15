class AddSyncFieldsToInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :last_sync_at, :datetime
    add_column :invoices, :sync_status, :string
    add_column :invoices, :sync_error, :text
  end
end
