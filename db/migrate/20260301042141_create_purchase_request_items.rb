# db/migrate/20260301040000_create_purchase_request_items.rb
class CreatePurchaseRequestItems < ActiveRecord::Migration[8.1]
  def change
    create_table :purchase_request_items do |t|
      t.references :purchase_request, null: false, foreign_key: true
      t.references :part, null: false, foreign_key: true
      t.integer :quantity, null: false, default: 1
      t.decimal :estimated_unit_price, precision: 10, scale: 2
      t.text :notes
      t.string :status, default: 'pending'
      
      t.timestamps
    end
    
    add_index :purchase_request_items, [:purchase_request_id, :part_id], unique: true, name: 'idx_purchase_request_items_unique'
  end
end