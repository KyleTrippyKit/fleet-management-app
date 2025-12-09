class CreateTrips < ActiveRecord::Migration[7.0]
  def change
    create_table :trips do |t|
      t.references :vehicle, null: false, foreign_key: true
      t.references :driver, foreign_key: { to_table: :users } # optional
      t.datetime :start_time, null: false
      t.datetime :end_time, null: false
      t.decimal :distance_km, precision: 10, scale: 2, default: 0.0

      t.timestamps
    end

    add_index :trips, :start_time
    add_index :trips, :end_time
  end
end
