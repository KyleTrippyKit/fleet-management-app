class CreateVendorRfqResponses < ActiveRecord::Migration[8.1]
  def change
    create_table :vendor_rfq_responses do |t|
      t.bigint :rfq_id, null: false
      t.bigint :supplier_id, null: false

      t.string :vendor_quote_number
      t.date   :quote_date
      t.date   :valid_until

      t.integer :lead_time_days
      t.decimal :total_amount, precision: 15, scale: 2, null: false, default: 0

      t.string :status, null: false, default: "received" # received/awarded/rejected
      t.text   :notes

      t.timestamps
    end

    add_index :vendor_rfq_responses, [:rfq_id, :supplier_id], unique: true
    add_index :vendor_rfq_responses, :status

    add_foreign_key :vendor_rfq_responses, :rfqs
    add_foreign_key :vendor_rfq_responses, :suppliers
  end
end
