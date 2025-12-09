class AddMileageToMaintenances < ActiveRecord::Migration[8.1]
  def change
    add_column :maintenances, :mileage, :integer
  end
end
