class AddPoTrackingToVendorRfqs < ActiveRecord::Migration[8.1]
  def change
    add_column :vendor_rfqs, :po_sent_at, :datetime
    add_column :vendor_rfqs, :po_received_at, :datetime
    add_column :vendor_rfqs, :po_status, :string
  end
end
