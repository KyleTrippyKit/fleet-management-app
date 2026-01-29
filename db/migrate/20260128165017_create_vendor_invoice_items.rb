# db/migrate/xxxx_create_vendor_invoice_items.rb
class CreateVendorInvoiceItems < ActiveRecord::Migration[8.1]
  def change
    create_table :vendor_invoice_items do |t|
      t.references :vendor_invoice, null: false, foreign_key: true
      t.references :part, foreign_key: true
      t.string :description
      t.integer :quantity, default: 1
      t.decimal :unit_price, precision: 10, scale: 2
      t.decimal :total_price, precision: 10, scale: 2
      t.text :notes

      t.timestamps
    end
  end
end