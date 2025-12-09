class AddServiceOwnerAndColorToVehicles < ActiveRecord::Migration[7.0]
  def change
    add_column :vehicles, :service_owner, :string
  end
end
