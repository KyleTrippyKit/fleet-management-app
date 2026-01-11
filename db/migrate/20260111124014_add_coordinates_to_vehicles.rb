# db/migrate/YYYYMMDDHHMMSS_add_coordinates_to_vehicles.rb
class AddCoordinatesToVehicles < ActiveRecord::Migration[7.0]
  def change
    add_column :vehicles, :latitude, :decimal, precision: 10, scale: 6
    add_column :vehicles, :longitude, :decimal, precision: 10, scale: 6
    add_index :vehicles, [:latitude, :longitude]
  end
end