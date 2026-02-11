class CreateVendorQuotationLines < ActiveRecord::Migration[8.1]
  def change
    create_table :vendor_quotation_lines do |t|
      t.references :vendor_quotation, null: false, foreign_key: true
      t.references :part, null: false, foreign_key: true
      t.text :description
      t.integer :quantity
      t.decimal :unit_price
      t.decimal :total_price

      t.timestamps
    end
  end
end
