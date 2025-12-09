class AddRegistrationNumberToVehicles < ActiveRecord::Migration[8.1]
  def change
    add_column :vehicles, :registration_number, :string
  end
end
