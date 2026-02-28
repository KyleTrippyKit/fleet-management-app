class CreateVehicleStatuses < ActiveRecord::Migration[8.1]
  def change
    create_table :vehicle_statuses do |t|
      t.references :vehicle, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }, null: true
      t.string :status, null: false
      t.text :notes
      t.boolean :current, default: false
      t.timestamps
    end
    
    add_index :vehicle_statuses, [:vehicle_id, :current]
    add_index :vehicle_statuses, :status
    add_index :vehicle_statuses, :created_at
  end
end