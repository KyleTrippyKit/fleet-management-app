class CreatePurchaseOrderItems < ActiveRecord::Migration[8.1]
  def change
    create_table :purchase_order_items do |t|
      t.bigint :purchase_order_id, null: false
      t.bigint :part_id
      t.string :description, null: false
      t.integer :quantity, null: false, default: 1
      t.decimal :unit_price, precision: 10, scale: 2, null: false
      t.decimal :total_price, precision: 10, scale: 2
      t.text :notes
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      
      t.index :purchase_order_id
      t.index :part_id
      t.check_constraint "quantity > 0", name: "positive_quantity"
    end
    
    add_foreign_key :purchase_order_items, :purchase_orders
    add_foreign_key :purchase_order_items, :parts
  end
end