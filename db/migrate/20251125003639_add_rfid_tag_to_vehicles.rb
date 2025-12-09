class AddRfidTagToVehicles < ActiveRecord::Migration[8.1]
  def change
    add_column :vehicles, :rfid_tag, :string
    add_index :vehicles, :rfid_tag, unique: true
  end
end
