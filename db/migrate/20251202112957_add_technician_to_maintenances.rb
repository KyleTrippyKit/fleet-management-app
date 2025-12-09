class AddTechnicianToMaintenances < ActiveRecord::Migration[8.1]
  def change
    add_column :maintenances, :technician, :string
  end
end
