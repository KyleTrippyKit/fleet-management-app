# db/migrate/20260331012000_add_only_missing_workflow_columns.rb
class AddOnlyMissingWorkflowColumns < ActiveRecord::Migration[8.1]
  def up
    # Check which columns are missing and add them
    unless column_exists?(:inspections, :qc_passed_at)
      add_column :inspections, :qc_passed_at, :datetime
    end
    
    unless column_exists?(:inspections, :rework_required)
      add_column :inspections, :rework_required, :boolean, default: false
    end
    
    unless column_exists?(:inspections, :rework_reason)
      add_column :inspections, :rework_reason, :text
    end
    
    unless column_exists?(:inspections, :additional_work_approved)
      add_column :inspections, :additional_work_approved, :boolean, default: false
    end
    
    unless column_exists?(:inspections, :final_invoice_generated_at)
      add_column :inspections, :final_invoice_generated_at, :datetime
    end
    
    unless column_exists?(:inspections, :final_invoice_number)
      add_column :inspections, :final_invoice_number, :string
    end
    
    unless column_exists?(:inspections, :has_additional_findings)
      add_column :inspections, :has_additional_findings, :boolean, default: false
    end
    
    unless column_exists?(:inspections, :cancelled_at)
      add_column :inspections, :cancelled_at, :datetime
    end
    
    unless column_exists?(:inspections, :cancellation_reason)
      add_column :inspections, :cancellation_reason, :text
    end
    
    unless column_exists?(:inspections, :started_at)
      add_column :inspections, :started_at, :datetime
    end
    
    # Add indexes for the new columns if they don't exist
    unless index_exists?(:inspections, :qc_passed_at)
      add_index :inspections, :qc_passed_at
    end
    
    unless index_exists?(:inspections, :final_invoice_generated_at)
      add_index :inspections, :final_invoice_generated_at
    end
    
    unless index_exists?(:inspections, :has_additional_findings)
      add_index :inspections, :has_additional_findings
    end
  end

  def down
    # Remove columns if they exist (for rollback)
    remove_column :inspections, :qc_passed_at if column_exists?(:inspections, :qc_passed_at)
    remove_column :inspections, :rework_required if column_exists?(:inspections, :rework_required)
    remove_column :inspections, :rework_reason if column_exists?(:inspections, :rework_reason)
    remove_column :inspections, :additional_work_approved if column_exists?(:inspections, :additional_work_approved)
    remove_column :inspections, :final_invoice_generated_at if column_exists?(:inspections, :final_invoice_generated_at)
    remove_column :inspections, :final_invoice_number if column_exists?(:inspections, :final_invoice_number)
    remove_column :inspections, :has_additional_findings if column_exists?(:inspections, :has_additional_findings)
    remove_column :inspections, :cancelled_at if column_exists?(:inspections, :cancelled_at)
    remove_column :inspections, :cancellation_reason if column_exists?(:inspections, :cancellation_reason)
    remove_column :inspections, :started_at if column_exists?(:inspections, :started_at)
    
    # Remove indexes
    remove_index :inspections, :qc_passed_at if index_exists?(:inspections, :qc_passed_at)
    remove_index :inspections, :final_invoice_generated_at if index_exists?(:inspections, :final_invoice_generated_at)
    remove_index :inspections, :has_additional_findings if index_exists?(:inspections, :has_additional_findings)
  end
end