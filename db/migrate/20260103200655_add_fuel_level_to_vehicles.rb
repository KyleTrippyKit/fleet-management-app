class AddFuelLevelToVehicles < ActiveRecord::Migration[8.1]
  def change
    add_column :vehicles, :fuel_level, :integer
  end
end
