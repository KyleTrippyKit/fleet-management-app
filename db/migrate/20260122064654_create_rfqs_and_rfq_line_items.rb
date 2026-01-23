# db/migrate/20250120_create_rfqs_and_rfq_line_items.rb
class CreateRfqsAndRfqLineItems < ActiveRecord::Migration[8.1]
  def change
    create_table :rfqs do |t|
      t.bigint :requesting_agency_id, null: false
      t.bigint :processing_agency_id  # VMCOTT's agency ID
      t.string :rfq_number, null: false
      t.string :status, default: "draft"  # draft, submitted, under_review, quoted, rejected, accepted
      t.date :request_date, null: false
      t.date :response_due_date
      t.text :description
      t.bigint :vehicle_id
      t.bigint :maintenance_request_id
      t.bigint :converted_to_quotation_id
      t.jsonb :priority_data, default: {}
      t.string :urgency
      t.text :special_instructions

      t.timestamps

      t.index [:processing_agency_id], name: "index_rfqs_on_processing_agency_id"
      t.index [:requesting_agency_id], name: "index_rfqs_on_requesting_agency_id"
      t.index [:rfq_number], name: "index_rfqs_on_rfq_number", unique: true
      t.index [:status], name: "index_rfqs_on_status"
      t.index [:vehicle_id], name: "index_rfqs_on_vehicle_id"
    end

    create_table :rfq_line_items do |t|
      t.bigint :rfq_id, null: false
      t.string :description, null: false
      t.integer :quantity, default: 1, null: false
      t.string :unit_of_measure
      t.text :specifications
      t.string :part_number
      t.string :category  # parts, labor, other

      t.timestamps

      t.index [:rfq_id], name: "index_rfq_line_items_on_rfq_id"
    end

    # Add foreign key constraints
    add_foreign_key :rfqs, :agencies, column: :requesting_agency_id
    add_foreign_key :rfqs, :agencies, column: :processing_agency_id
    add_foreign_key :rfqs, :vehicles
    add_foreign_key :rfqs, :maintenance_requests
    add_foreign_key :rfq_line_items, :rfqs
  end
end