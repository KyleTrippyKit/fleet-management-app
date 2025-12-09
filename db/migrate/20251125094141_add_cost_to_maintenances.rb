class AddCostToMaintenances < ActiveRecord::Migration[8.1]
  def change
    add_column :maintenances, :cost, :decimal
  end
end
