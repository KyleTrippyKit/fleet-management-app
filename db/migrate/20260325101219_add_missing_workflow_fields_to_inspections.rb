# db/migrate/YYYYMMDDHHMMSS_add_missing_workflow_fields_to_inspections.rb
class AddMissingWorkflowFieldsToInspections < ActiveRecord::Migration[8.1]
  def change
    # Add fields that are in WorkflowManager but missing from schema
    add_column :inspections, :client_type, :string
    add_column :inspections, :payment_terms, :string
    add_column :inspections, :rejection_reason, :text
    add_column :inspections, :hold_reason, :text
    add_column :inspections, :paused_at, :datetime
    add_column :inspections, :paused_reason, :text
    add_column :inspections, :blocked_at, :datetime
    add_column :inspections, :blocked_reason, :text
    add_column :inspections, :qc_failed_at, :datetime
    add_column :inspections, :qc_failure_reason, :text
    add_column :inspections, :rework_completed_at, :datetime
    add_column :inspections, :paid_at, :datetime
    add_column :inspections, :actual_pickup_date, :datetime
    add_column :inspections, :picked_up_by, :string
    add_column :inspections, :intake_photos, :jsonb, default: []
    add_column :inspections, :final_photos, :jsonb, default: []
    add_column :inspections, :customer_signature, :string
    add_column :inspections, :labor_rate, :decimal, precision: 10, scale: 2
    add_column :inspections, :parts_markup_percentage, :integer, default: 30
    add_column :inspections, :total_estimated_cost, :decimal, precision: 10, scale: 2
    add_column :inspections, :received_at, :datetime
    add_column :inspections, :no_work_needed, :boolean, default: false
    
    # Add indexes for performance
    add_index :inspections, :client_type
    add_index :inspections, :received_at
    add_index :inspections, :paid_at
    add_index :inspections, :picked_up_by
  end
end