class CreateQuotationLineItems < ActiveRecord::Migration[8.1]
  def change
    create_table :quotation_line_items do |t|
      t.references :quotation, null: false, foreign_key: true
      t.text :description
      t.integer :quantity
      t.decimal :unit_price
      t.text :specifications

      t.timestamps
    end
  end
end
