class AddDetailsToMaintenances < ActiveRecord::Migration[8.1]
  def change
    add_column :maintenances, :details, :text
  end
end
