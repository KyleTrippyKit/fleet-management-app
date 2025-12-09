class CreateMaintenances < ActiveRecord::Migration[8.1]
  def change
    create_table :maintenances do |t|
      t.references :vehicle, null: false, foreign_key: true
      t.references :service_provider, null: false, foreign_key: true
      t.string :service_type
      t.date :start_date
      t.date :end_date
      t.string :status

      t.timestamps
    end
  end
end
