class CreateVendorRfqItems < ActiveRecord::Migration[8.1]
  def change
    create_table :vendor_rfq_items do |t|
      t.references :vendor_rfq, null: false, foreign_key: true
      t.references :part, null: false, foreign_key: true
      t.text :description
      t.integer :quantity
      t.string :unit_of_measure

      t.timestamps
    end
  end
end
