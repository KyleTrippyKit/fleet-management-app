class CreateVendorQuotations < ActiveRecord::Migration[8.1]
  def change
    create_table :vendor_quotations do |t|
      t.references :vendor_rfq, null: false, foreign_key: true
      t.references :supplier, null: false, foreign_key: true
      t.string :status
      t.text :notes
      t.string :currency

      t.timestamps
    end
  end
end
