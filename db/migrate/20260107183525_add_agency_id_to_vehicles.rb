class AddAgencyIdToVehicles < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:vehicles, :agency_id)
      add_reference :vehicles, :agency, null: false, foreign_key: true
    end
  end
end