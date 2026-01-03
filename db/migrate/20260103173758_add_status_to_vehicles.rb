# db/migrations/[timestamp]_add_status_to_vehicles.rb
class AddStatusToVehicles < ActiveRecord::Migration[8.1]
  def change
    add_column :vehicles, :status, :string, default: 'active'
  end
end