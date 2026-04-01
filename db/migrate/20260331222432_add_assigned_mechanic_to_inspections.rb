class AddAssignedMechanicToInspections < ActiveRecord::Migration[8.1]
  def change
    add_column :inspections, :assigned_mechanic_id, :integer
  end
end
