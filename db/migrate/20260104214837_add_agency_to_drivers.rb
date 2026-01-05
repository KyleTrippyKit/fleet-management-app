class AddAgencyToDrivers < ActiveRecord::Migration[8.1]
  def change
    add_reference :drivers, :agency, null: false, foreign_key: true
  end
end
