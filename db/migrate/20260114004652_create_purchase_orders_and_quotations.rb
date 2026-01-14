# db/migrate/20260114010000_create_purchase_orders_and_quotations.rb
class CreatePurchaseOrdersAndQuotations < ActiveRecord::Migration[8.1]
  def change
    # Create purchase_orders table
    create_table :purchase_orders do |t|
      t.string :po_number, null: false
      t.string :vendor, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.integer :status, default: 0
      t.references :vehicle, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :approved_by, foreign_key: { to_table: :users }
      t.datetime :approved_at
      t.text :notes
      
      t.timestamps
    end
    
    add_index :purchase_orders, :po_number, unique: true
    
    # Create quotations table
    create_table :quotations do |t|
      t.string :quote_number, null: false
      t.string :vendor, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.integer :status, default: 0
      t.references :vehicle, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.date :valid_from
      t.date :valid_to
      t.text :notes
      
      t.timestamps
    end
    
    add_index :quotations, :quote_number, unique: true
    
    # Create pos_transactions table (if it doesn't exist)
    unless table_exists?(:pos_transactions)
      create_table :pos_transactions do |t|
        t.string :transaction_id, null: false
        t.decimal :amount, precision: 10, scale: 2, null: false
        t.integer :payment_type, default: 0
        t.integer :status, default: 0
        t.references :invoice, foreign_key: true
        t.references :vehicle, foreign_key: true
        t.references :user, foreign_key: true
        t.text :notes
        
        t.timestamps
      end
      
      add_index :pos_transactions, :transaction_id, unique: true
    end
  end
end