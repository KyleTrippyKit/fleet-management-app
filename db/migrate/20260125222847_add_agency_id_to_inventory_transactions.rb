class AddAgencyIdToInventoryTransactions < ActiveRecord::Migration[8.1]
  def change
    add_reference :inventory_transactions, :agency, foreign_key: true
    
    # If you want to backfill existing records
    reversible do |dir|
      dir.up do
        # Set agency_id based on user's agency or use a default
        execute <<-SQL
          UPDATE inventory_transactions 
          SET agency_id = users.agency_id 
          FROM users 
          WHERE inventory_transactions.user_id = users.id
        SQL
        
        # Set agency_id = 1 for any remaining nulls (if you have agency with id 1)
        execute "UPDATE inventory_transactions SET agency_id = 1 WHERE agency_id IS NULL"
      end
    end
  end
end