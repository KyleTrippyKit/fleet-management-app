# db/migrate/20260115165700_add_quickbooks_id_to_transactions.rb
class AddQuickbooksIdToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :quickbooks_id, :string
    add_index :transactions, :quickbooks_id
  end
end