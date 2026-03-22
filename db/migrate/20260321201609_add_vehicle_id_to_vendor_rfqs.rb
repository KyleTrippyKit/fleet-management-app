# db/migrate/XXXXXXXXXXXXXX_add_vehicle_id_to_vendor_rfqs.rb
class AddVehicleIdToVendorRfqs < ActiveRecord::Migration[7.0]
  def change
    add_reference :vendor_rfqs, :vehicle, foreign_key: true, null: true
  end
end