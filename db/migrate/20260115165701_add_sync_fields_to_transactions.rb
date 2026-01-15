# db/migrate/20260115165701_add_sync_fields_to_transactions.rb
class AddSyncFieldsToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :last_sync_at, :datetime
    add_column :transactions, :sync_status, :string, default: 'pending'
    add_column :transactions, :sync_error, :text
    
    add_index :transactions, :sync_status
    add_index :transactions, [:sync_status, :last_sync_at]
  end
end