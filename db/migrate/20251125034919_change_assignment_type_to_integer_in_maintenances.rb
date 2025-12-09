class ChangeAssignmentTypeToIntegerInMaintenances < ActiveRecord::Migration[8.1]
  def change
    change_column :maintenances, :assignment_type, :integer, default: 0, using: 'assignment_type::integer'
  end
end
