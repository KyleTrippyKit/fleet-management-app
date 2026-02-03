# db/migrate/XXXXXXXXXXXXXX_add_index_to_vehicles_license_plate.rb
class AddIndexToVehiclesLicensePlate < ActiveRecord::Migration[8.1]
  def change
    add_index :vehicles, :license_plate
  end
end
