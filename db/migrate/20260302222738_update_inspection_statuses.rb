# db/migrate/20260330_update_inspection_statuses.rb
class UpdateInspectionStatuses < ActiveRecord::Migration[8.1]
  def up
    # Update any inspections that were in awaiting_approval without workflow selected
    # to be in pending_supervisor_review
    execute <<-SQL
      UPDATE inspections 
      SET status = 'pending_supervisor_review' 
      WHERE status = 'awaiting_approval' 
      AND workflow_selected_by_id IS NULL
      AND created_at >= NOW() - INTERVAL '30 days'
    SQL
    
    # Update any inspections that were in awaiting_approval with workflow selected
    # to be in awaiting_approval (they stay as is)
    # This is just to ensure data consistency
    execute <<-SQL
      UPDATE inspections 
      SET status = 'awaiting_approval' 
      WHERE status = 'awaiting_approval' 
      AND workflow_selected_by_id IS NOT NULL
    SQL
  end

  def down
    # No need to revert as we're just updating statuses
    # The enum values will remain the same
  end
end