# db/migrate/20240306000001_create_vehicle_condition_reports.rb
class CreateVehicleConditionReports < ActiveRecord::Migration[7.1]
  def change
    create_table :vehicle_condition_reports do |t|
      # Associations
      t.references :vehicle, null: false, foreign_key: true
      t.references :reception_log, foreign_key: true, null: true
      t.references :security_officer, null: false, foreign_key: { to_table: :users }
      
      # Polymorphic client (Agency or Driver/Public)
      t.references :client, polymorphic: true, null: true
      
      # Core measurements
      t.integer :fuel_level, null: false
      t.integer :odometer, null: false
      
      # JSON storage for flexible condition data
      t.jsonb :condition_data, default: {}
      t.jsonb :acknowledgment, default: {}
      
      # Status
      t.string :status, default: 'draft'
      
      # Timestamps
      t.datetime :signed_at
      t.timestamps
    end
    
    # Indexes for performance
    add_index :vehicle_condition_reports, :condition_data, using: :gin
    add_index :vehicle_condition_reports, :acknowledgment, using: :gin
    add_index :vehicle_condition_reports, :status
    add_index :vehicle_condition_reports, :signed_at
    add_index :vehicle_condition_reports, [:vehicle_id, :created_at]
  end
end