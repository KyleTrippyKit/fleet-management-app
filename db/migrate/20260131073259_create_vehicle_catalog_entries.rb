class CreateVehicleCatalogEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :vehicle_catalog_entries do |t|
      t.string  :make,  null: false
      t.string  :model, null: false
      t.string  :vehicle_type
      t.integer :year_from
      t.integer :year_to
      t.timestamps
    end

    add_index :vehicle_catalog_entries, [:make, :model], unique: true
    add_index :vehicle_catalog_entries, :make
    add_index :vehicle_catalog_entries, :model
  end
end
