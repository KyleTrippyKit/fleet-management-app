class AddDetailsToVehicles < ActiveRecord::Migration[8.1]
  def change
    add_column :vehicles, :owner, :string
    add_column :vehicles, :color, :string
    add_column :vehicles, :chassis_number, :string
    add_column :vehicles, :year_of_manufacture, :integer
    add_column :vehicles, :serial_number, :string
    add_column :vehicles, :vehicle_type, :string
    add_column :vehicles, :picture, :string
  end
end
