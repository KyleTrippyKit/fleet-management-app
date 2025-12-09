# db/migrate/[timestamp]_change_assignment_type_to_string_in_maintenances.rb
class ChangeAssignmentTypeToStringInMaintenances < ActiveRecord::Migration[7.1]
  def change
    change_column :maintenances, :assignment_type, :string
  end
end
