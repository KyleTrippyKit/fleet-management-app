# db/migrate/20260301000000_add_workflow_fields_to_inspections.rb
class AddWorkflowFieldsToInspections < ActiveRecord::Migration[8.1]
  def change
    add_column :inspections, :status, :string, default: 'pending_inspection'
    add_column :inspections, :parts_coordinator_notified_at, :datetime
    add_column :inspections, :billing_notified_at, :datetime
    add_column :inspections, :mechanic_notified_at, :datetime
    
    add_column :inspections, :final_inspection_completed_at, :datetime
    add_column :inspections, :final_inspection_notes, :text
    add_column :inspections, :final_inspector_id, :bigint
    add_index :inspections, :final_inspector_id
    
    add_column :inspections, :ready_for_pickup_at, :datetime
    add_column :inspections, :pickup_notified_at, :datetime
    
    add_foreign_key :inspections, :users, column: :final_inspector_id
  end
end