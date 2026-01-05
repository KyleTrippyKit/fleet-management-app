class AddAgencyToVehicles < ActiveRecord::Migration[8.1]
  def change
    add_reference :vehicles, :agency, null: false, foreign_key: true
  end
end
