# db/migrate/20260301000001_create_parts_requests.rb
class CreatePartsRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :parts_requests do |t|
      t.references :inspection, null: false, foreign_key: true
      t.references :part, null: false, foreign_key: true
      t.integer :quantity, null: false, default: 1
      t.string :status, default: 'pending'
      t.boolean :in_stock, default: false
      t.references :vendor_invoice_id, foreign_key: { to_table: :vendor_invoices }
      t.references :purchase_order_id, foreign_key: { to_table: :purchase_orders }
      t.datetime :notified_parts_coordinator_at
      t.datetime :notified_billing_at
      t.datetime :parts_received_at
      t.datetime :approved_at
      t.datetime :rejected_at
      t.text :rejection_reason
      t.timestamps
    end
    
    add_index :parts_requests, [:inspection_id, :part_id], unique: true
  end
end