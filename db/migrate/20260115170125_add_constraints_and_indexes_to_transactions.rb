# db/migrate/20260115170125_add_constraints_and_indexes_to_transactions.rb
class AddConstraintsAndIndexesToTransactions < ActiveRecord::Migration[8.1]
  def change
    # Ensure quickbooks_id can be null (for unsynced transactions)
    change_column_null :transactions, :quickbooks_id, true
    
    # Add more specific indexes for better query performance
    add_index :transactions, [:quickbooks_id, :last_sync_at]
    
    # Optional: PostgreSQL CHECK constraint for sync_status
    # Only uncomment if using PostgreSQL
    # reversible do |dir|
    #   dir.up do
    #     execute <<-SQL
    #       ALTER TABLE transactions 
    #       ADD CONSTRAINT check_sync_status 
    #       CHECK (sync_status IN ('pending', 'syncing', 'success', 'failed', 'error'))
    #     SQL
    #   end
    #   dir.down do
    #     execute "ALTER TABLE transactions DROP CONSTRAINT IF EXISTS check_sync_status;"
    #   end
    # end
  end
end