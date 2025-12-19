class CreateDriversVehiclesJoinTable < ActiveRecord::Migration[7.0]
  def change
    create_table :drivers_vehicles, id: false do |t|
      t.references :driver, null: false, foreign_key: true
      t.references :vehicle, null: false, foreign_key: true
    end

    add_index :drivers_vehicles, [:driver_id, :vehicle_id], unique: true
  end
end
