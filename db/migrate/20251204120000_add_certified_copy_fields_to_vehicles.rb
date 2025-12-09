class AddCertifiedCopyFieldsToVehicles < ActiveRecord::Migration[8.1]
  def change
    add_column :vehicles, :engine_number, :string
    add_column :vehicles, :fuel_type, :string
    add_column :vehicles, :transmission, :string
    add_column :vehicles, :body_style, :string
    add_column :vehicles, :modifications, :text
  end
end
