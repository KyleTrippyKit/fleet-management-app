class AddMileageToVehicles < ActiveRecord::Migration[8.1]
  def change
    add_column :vehicles, :mileage, :integer
  end
end
