class CreateDrivers < ActiveRecord::Migration[7.1]
  def change
    create_table :drivers do |t|
      t.string :name, null: false
      t.string :license_number
      t.string :phone
      t.string :status, default: "active"
      t.text :notes

      t.timestamps
    end
  end
end
