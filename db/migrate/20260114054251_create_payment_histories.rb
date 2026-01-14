# db/migrate/YYYYMMDDHHMMSS_create_payment_histories.rb
class CreatePaymentHistories < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_histories do |t|
      t.references :invoice, null: false, foreign_key: true
      t.bigint :payment_transaction_id, null: false
      t.date :payment_date, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :payment_method
      t.string :reference_number
      t.text :notes
      t.string :status, default: 'completed'
      t.timestamps
      
      t.index :payment_date
      t.index :status
      t.index :reference_number
      t.index :payment_transaction_id, unique: true
    end
    
    # Add foreign key constraint separately
    add_foreign_key :payment_histories, :transactions, column: :payment_transaction_id
  end
end