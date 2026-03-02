class AddWorkflowFieldsToMaintenance < ActiveRecord::Migration[8.1]
  def change
    # Track additional work
    add_column :maintenances, :additional_work, :boolean, default: false
    add_reference :maintenances, :parent_maintenance, foreign_key: { to_table: :maintenances }
    
    # Track agency decisions
    add_column :maintenances, :cancelled_by_agency, :boolean, default: false
    add_column :maintenances, :agency_decision_at, :datetime
    add_column :maintenances, :agency_decision_notes, :text
  end
end