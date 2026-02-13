# db/migrate/20260211082753_create_vendor_rfqs.rb
class CreateVendorRfqs < ActiveRecord::Migration[8.1]
  def change
    create_table :vendor_rfqs do |t|
      t.string :rfq_number, null: false
      t.string :status, null: false, default: "draft"
      t.date :sent_date
      t.date :due_date
      t.text :notes

      # FIX: correct FK targets
      t.references :created_by, null: true, foreign_key: { to_table: :users }
      t.references :processing_agency, null: true, foreign_key: { to_table: :agencies }

      t.timestamps
    end

    add_index :vendor_rfqs, :rfq_number, unique: true
    add_index :vendor_rfqs, :status
  end
end
