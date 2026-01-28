# db/migrate/20260125130000_create_purchase_requests.rb
class CreatePurchaseRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :purchase_requests do |t|
      t.references :part, null: false, foreign_key: true
      t.references :quotation, null: true, foreign_key: true
      t.references :requested_by, null: false, foreign_key: { to_table: :users }
      t.references :approved_by, foreign_key: { to_table: :users }
      
      t.integer :quantity, null: false
      t.string :urgency, default: 'normal'
      t.text :notes
      t.string :status, default: 'pending'
      
      t.datetime :approved_at
      t.datetime :ordered_at
      t.datetime :received_at
      
      t.timestamps
    end
    
    add_index :purchase_requests, :status
    add_index :purchase_requests, :urgency
    add_index :purchase_requests, [:part_id, :status]
  end
end