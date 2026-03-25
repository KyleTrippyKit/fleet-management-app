# db/migrate/20260325101233_add_missing_workflow_fields_to_inspection_jobs.rb
class AddMissingWorkflowFieldsToInspectionJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :inspection_jobs, :paused_at, :datetime
    add_column :inspection_jobs, :paused_reason, :text
    add_column :inspection_jobs, :rework_requested_at, :datetime
    add_column :inspection_jobs, :rework_reason, :text
    add_column :inspection_jobs, :actual_labor_cost, :decimal, precision: 10, scale: 2
    add_column :inspection_jobs, :actual_parts_cost, :decimal, precision: 10, scale: 2
    add_column :inspection_jobs, :started_at, :datetime
    add_column :inspection_jobs, :assigned_at, :datetime
    # REMOVE this line - status already exists!
    # add_column :inspection_jobs, :status, :string, default: "pending_mechanic_review"
    
    add_index :inspection_jobs, :started_at
    add_index :inspection_jobs, :paused_at
  end
end