# db/migrate/xxxxxx_create_inspections.rb
class CreateInspections < ActiveRecord::Migration[8.1]
  def change
    create_table :inspections do |t|
      t.references :vehicle, null: false, foreign_key: true
      t.references :inspector, null: false, foreign_key: { to_table: :users }
      t.references :purchase_order, foreign_key: true
      t.datetime :completed_at
      t.integer :mileage_at_inspection
      t.text :notes
      t.integer :next_service_mileage
      t.date :next_service_date

      t.timestamps
    end
  end
end