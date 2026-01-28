class CreateInventoryTransactions < ActiveRecord::Migration[8.1]
  def up
    # First, drop any existing table fragments
    execute "DROP TABLE IF EXISTS inventory_transactions CASCADE"
    
    # Create the table
    create_table :inventory_transactions do |t|
      t.string :transaction_type, null: false
      t.decimal :quantity, precision: 10, scale: 2, null: false
      t.text :notes
      
      # Polymorphic associations
      t.references :inventory_item, polymorphic: true, null: false
      t.references :reference, polymorphic: true
      
      # User who performed the transaction
      t.references :user, foreign_key: true
      
      t.timestamps
    end
    
    # Add indexes with explicit error handling
    begin
      add_index :inventory_transactions, [:inventory_item_type, :inventory_item_id], 
                name: "idx_inventory_transactions_on_inventory_item"
    rescue ActiveRecord::StatementInvalid => e
      puts "Index idx_inventory_transactions_on_inventory_item already exists or error: #{e.message}"
    end
    
    begin
      add_index :inventory_transactions, [:reference_type, :reference_id], 
                name: "idx_inventory_transactions_on_reference"
    rescue ActiveRecord::StatementInvalid => e
      puts "Index idx_inventory_transactions_on_reference already exists or error: #{e.message}"
    end
    
    begin
      add_index :inventory_transactions, :transaction_type
    rescue ActiveRecord::StatementInvalid => e
      puts "Index on transaction_type already exists or error: #{e.message}"
    end
    
    begin
      add_index :inventory_transactions, :created_at
    rescue ActiveRecord::StatementInvalid => e
      puts "Index on created_at already exists or error: #{e.message}"
    end
    
    begin
      add_index :inventory_transactions, :user_id
    rescue ActiveRecord::StatementInvalid => e
      puts "Index on user_id already exists or error: #{e.message}"
    end
  end
  
  def down
    drop_table :inventory_transactions
  end
end