class AddPriceColumnsToInventoryTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :inventory_transactions, :unit_price, :decimal, precision: 10, scale: 2
    add_column :inventory_transactions, :total_price, :decimal, precision: 10, scale: 2
    add_column :inventory_transactions, :previous_quantity, :integer
    add_column :inventory_transactions, :new_quantity, :integer
  end
end