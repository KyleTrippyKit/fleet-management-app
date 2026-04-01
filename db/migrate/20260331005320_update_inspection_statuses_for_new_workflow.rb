# db/migrate/YYYYMMDDHHMMSS_update_inspection_statuses_for_new_workflow.rb
class UpdateInspectionStatusesForNewWorkflow < ActiveRecord::Migration[8.1]
  def up
    # Update legacy status 'approved_for_repair' to 'approved'
    execute <<-SQL
      UPDATE inspections 
      SET status = 'approved' 
      WHERE status = 'approved_for_repair'
    SQL
  end

  def down
    # Reverse: change 'approved' back to 'approved_for_repair'
    execute <<-SQL
      UPDATE inspections 
      SET status = 'approved_for_repair' 
      WHERE status = 'approved'
    SQL
  end
end