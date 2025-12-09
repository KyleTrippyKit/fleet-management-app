class CreateDamageReports < ActiveRecord::Migration[8.1]
  def change
    create_table :damage_reports do |t|
      t.references :vehicle, null: false, foreign_key: true
      t.text :description

      t.timestamps
    end
  end
end
