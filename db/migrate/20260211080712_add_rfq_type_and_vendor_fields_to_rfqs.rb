class AddRfqTypeAndVendorFieldsToRfqs < ActiveRecord::Migration[8.1]
  def change
    add_column :rfqs, :rfq_type, :string, null: false, default: "agency_to_vmcott"
    add_index  :rfqs, :rfq_type

    # For VMCOTT->Vendor RFQs (vendors are Suppliers in your system)
    add_column :rfqs, :vendor_supplier_ids, :jsonb, null: false, default: []
    add_column :rfqs, :awarded_supplier_id, :bigint
    add_index  :rfqs, :awarded_supplier_id

    add_column :rfqs, :title, :string
  end
end
