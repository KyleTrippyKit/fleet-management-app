class AddPartTrackingToMaintenances < ActiveRecord::Migration[8.1]
  def change
    # Add columns for part tracking
    add_column :maintenances, :parts_used, :text
    add_column :maintenances, :parts_cost, :decimal, precision: 10, scale: 2
    add_column :maintenances, :labor_hours, :decimal, precision: 5, scale: 2
    add_column :maintenances, :labor_rate, :decimal, precision: 10, scale: 2
  end
end
