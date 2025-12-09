class CreateMaintenanceParts < ActiveRecord::Migration[8.1]
  def change
    create_table :maintenance_parts do |t|
      t.references :maintenance, null: false, foreign_key: true
      t.references :part, null: false, foreign_key: true
      t.integer :quantity_needed

      t.timestamps
    end
  end
end
