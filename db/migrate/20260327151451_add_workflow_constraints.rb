# db/migrate/20260341000004_add_workflow_constraints.rb
class AddWorkflowConstraints < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :work_orders, 
      "status IN ('received','inspected','awaiting_approval','approved','in_progress','on_hold','ready_for_pickup','completed','cancelled')",
      name: "work_order_status_check"
    
    add_check_constraint :job_tasks, 
      "status IN ('pending','approved','in_progress','blocked','completed','skipped')",
      name: "job_task_status_check"
    
    add_check_constraint :work_sessions, 
      "session_type IN ('work','break','waiting','blocked')",
      name: "work_session_type_check"
    
    add_check_constraint :work_sessions, 
      "duration_hours >= 0",
      name: "positive_duration_check"
    
    add_check_constraint :work_sessions, 
      "ended_at IS NULL OR ended_at >= started_at",
      name: "valid_time_range_check"
  end
end