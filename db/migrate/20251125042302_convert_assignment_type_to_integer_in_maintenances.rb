class ConvertAssignmentTypeToIntegerInMaintenances < ActiveRecord::Migration[8.1]
  def up
    add_column :maintenances, :assignment_type_tmp, :integer, default: 0

    Maintenance.reset_column_information
    Maintenance.find_each do |m|
      m.update_column(:assignment_type_tmp, m.assignment_type == "purchasing" ? 1 : 0)
    end

    remove_column :maintenances, :assignment_type
    rename_column :maintenances, :assignment_type_tmp, :assignment_type
  end

  def down
    add_column :maintenances, :assignment_type_tmp, :string

    Maintenance.reset_column_information
    Maintenance.find_each do |m|
      m.update_column(:assignment_type_tmp, m.assignment_type == 1 ? "purchasing" : "stores")
    end

    remove_column :maintenances, :assignment_type
    rename_column :maintenances, :assignment_type_tmp, :assignment_type
  end
end
