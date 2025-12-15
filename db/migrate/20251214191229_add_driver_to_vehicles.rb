class AddDriverToVehicles < ActiveRecord::Migration[7.1]
  def change
    add_reference :vehicles, :driver, foreign_key: true
  end
end