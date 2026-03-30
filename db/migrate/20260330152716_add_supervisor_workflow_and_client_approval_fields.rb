# db/migrate/20260330120000_add_supervisor_workflow_and_client_approval_fields.rb
class AddSupervisorWorkflowAndClientApprovalFields < ActiveRecord::Migration[8.1]
  def change
    # Add supervisor selection tracking fields to inspections
    # workflow_type already exists (default: 'work_before_payment')
    unless column_exists?(:inspections, :workflow_selected_by_id)
      add_column :inspections, :workflow_selected_by_id, :integer
    end
    
    unless column_exists?(:inspections, :workflow_selected_at)
      add_column :inspections, :workflow_selected_at, :datetime
    end
    
    unless column_exists?(:inspections, :workflow_notes)
      add_column :inspections, :workflow_notes, :text
    end
    
    # Add client approval tracking fields to quotations
    unless column_exists?(:quotations, :client_approved_job_ids)
      add_column :quotations, :client_approved_job_ids, :jsonb, default: []
    end
    
    unless column_exists?(:quotations, :client_approved_part_ids)
      add_column :quotations, :client_approved_part_ids, :jsonb, default: []
    end
    
    unless column_exists?(:quotations, :client_po_number)
      add_column :quotations, :client_po_number, :string
    end
    
    unless column_exists?(:quotations, :client_po_uploaded_at)
      add_column :quotations, :client_po_uploaded_at, :datetime
    end
    
    # Add indexes for faster queries
    unless index_exists?(:inspections, :workflow_selected_by_id)
      add_index :inspections, :workflow_selected_by_id
    end
    
    # Add GIN index for JSONB columns on quotations
    unless index_exists?(:quotations, :client_approved_job_ids)
      add_index :quotations, :client_approved_job_ids, using: :gin
    end
    
    unless index_exists?(:quotations, :client_approved_part_ids)
      add_index :quotations, :client_approved_part_ids, using: :gin
    end
  end
end