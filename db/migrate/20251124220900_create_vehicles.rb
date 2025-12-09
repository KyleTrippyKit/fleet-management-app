class CreateVehicles < ActiveRecord::Migration[8.1]
  def change
    create_table :vehicles do |t|
      t.string :make
      t.string :model
      t.string :license_plate

      t.timestamps
    end
  end
end
