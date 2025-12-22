class AddNotNullConstraintToMaintenancesStartDateEndDate < ActiveRecord::Migration[8.1]
  def up
    # First, set default values for existing null records
    Maintenance.where(start_date: nil).update_all(start_date: Date.today)
    Maintenance.where(end_date: nil).update_all(end_date: Date.today)
    
    # Add not null constraints
    change_column_null :maintenances, :start_date, false
    change_column_null :maintenances, :end_date, false
  end

  def down
    change_column_null :maintenances, :start_date, true
    change_column_null :maintenances, :end_date, true
  end
end