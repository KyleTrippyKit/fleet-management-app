class AddDateAndDetailsToMaintenances < ActiveRecord::Migration[8.1]
  def change
    add_column :maintenances, :date, :date
    add_column :maintenances, :details, :text
  end
end
