class AddTimeZoneToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :time_zone, :string, default: "UTC"
    
    # Optional: Add index for faster queries
    add_index :users, :time_zone
  end
end