class DropVehicleUsages < ActiveRecord::Migration[8.1]
  def change
    drop_table :vehicle_usages
  end
end
