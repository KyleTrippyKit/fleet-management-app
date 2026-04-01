class AddForeignKeyToAssignedMechanicOnInspections < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :inspections, :users, column: :assigned_mechanic_id
  end
end