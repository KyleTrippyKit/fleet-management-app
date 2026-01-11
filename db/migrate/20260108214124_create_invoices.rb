# db/migrate/[timestamp]_create_invoices.rb
class CreateInvoices < ActiveRecord::Migration[7.0]
  def change
    create_table :invoices do |t|
      t.string :invoice_number, null: false
      t.references :vehicle, foreign_key: true, null: false
      t.string :vendor, null: false
      t.date :invoice_date, null: false
      t.date :due_date, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.decimal :subtotal, precision: 10, scale: 2
      t.decimal :tax, precision: 10, scale: 2
      t.string :status, default: 'pending'
      t.text :notes
      t.string :category
      t.references :maintenance, foreign_key: true
      t.timestamps
    end
    
    add_index :invoices, :invoice_number, unique: true
    add_index :invoices, :status
    add_index :invoices, :vendor
  end
end