class AddMaintenanceRefToMaintenanceTasks < ActiveRecord::Migration[8.1]
  def change
    add_reference :maintenance_tasks, :maintenance, null: false, foreign_key: true
  end
end
