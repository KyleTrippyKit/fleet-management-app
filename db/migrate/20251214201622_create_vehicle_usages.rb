class CreateVehicleUsages < ActiveRecord::Migration[8.1]
  def change
    create_table :vehicle_usages do |t|
      t.references :driver, null: false, foreign_key: true
      t.references :vehicle, null: false, foreign_key: true
      t.datetime :start_date
      t.datetime :end_date
      t.string :status

      t.timestamps
    end
  end
end
