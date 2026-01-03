class AddOwnerToMaintenances < ActiveRecord::Migration[8.1]
  def change
    add_column :maintenances, :owner, :string
  end
end
