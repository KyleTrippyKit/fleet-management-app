class AddServiceOwnerAndColorToVehicles < ActiveRecord::Migration[8.1]
  def change
    add_column :vehicles, :service_owner, :string
  end
end
