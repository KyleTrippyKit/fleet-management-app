class AddConstraintsToTransactions < ActiveRecord::Migration[8.1]
  def change
    # Allow null for quickbooks_id (good for new records)
    change_column_null :transactions, :quickbooks_id, true
    
    # Add default value for sync_status
    change_column_default :transactions, :sync_status, from: nil, to: 'pending'
    
    # Optional: Add check constraint for specific sync statuses
    # (This is PostgreSQL-specific)
    reversible do |dir|
      dir.up do
        execute <<-SQL
          ALTER TABLE transactions 
          ADD CONSTRAINT check_sync_status 
          CHECK (sync_status IN ('pending', 'syncing', 'success', 'failed', 'error'));
        SQL
      end
      dir.down do
        execute "ALTER TABLE transactions DROP CONSTRAINT IF EXISTS check_sync_status;"
      end
    end
  end
end