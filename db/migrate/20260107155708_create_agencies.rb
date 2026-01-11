class CreateAgencies < ActiveRecord::Migration[8.1]
  def change
    create_table :agencies do |t|
      t.string :name, null: false
      t.string :code             # remove unique: true from here
      t.text :description
      t.string :theme

      t.timestamps
    end

    # Add a unique index for code
    add_index :agencies, :code, unique: true
  end
end
