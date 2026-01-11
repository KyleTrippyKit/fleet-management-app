class CreateMaintenanceRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :maintenance_requests do |t|
      t.references :vehicle, null: false, foreign_key: true
      t.references :requesting_agency, null: false, foreign_key: { to_table: :agencies }
      t.references :processing_agency, foreign_key: { to_table: :agencies }
      t.text :description
      t.string :priority
      t.string :status, default: 'pending'
      t.date :requested_date
      t.date :completed_date
      t.text :notes

      t.timestamps
    end
  end
end