class AddLocationToVehicles < ActiveRecord::Migration[8.1]
  def change
    add_column :vehicles, :location, :string
    add_column :vehicles, :current_location, :string
  end
end
