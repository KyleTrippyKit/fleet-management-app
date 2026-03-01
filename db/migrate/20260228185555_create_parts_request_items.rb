class CreatePartsRequestItems < ActiveRecord::Migration[8.1]
  def change
    create_table :parts_request_items do |t|
      t.references :parts_request, null: false, foreign_key: true
      t.references :part, null: false, foreign_key: true
      t.integer :quantity_needed
      t.string :status

      t.timestamps
    end
  end
end
