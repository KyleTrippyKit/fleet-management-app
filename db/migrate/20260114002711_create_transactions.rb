# db/migrate/20260114002711_create_transactions.rb
class CreateTransactions < ActiveRecord::Migration[7.0]
  def change
    create_table :transactions do |t|
      t.references :invoice, foreign_key: true
      t.references :vehicle, foreign_key: true
      t.references :user, foreign_key: true
      
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :reference_number
      t.string :description
      t.string :payment_method
      t.integer :status, default: 0
      t.integer :transaction_type, default: 0
      t.text :notes
      
      t.timestamps
    end
    
    add_index :transactions, :reference_number, unique: true
    add_index :transactions, :status
    add_index :transactions, :transaction_type
  end
end