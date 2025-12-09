class AddCategoryToMaintenances < ActiveRecord::Migration[7.1]
  def change
    add_column :maintenances, :category, :string, default: "General"
  end
end
