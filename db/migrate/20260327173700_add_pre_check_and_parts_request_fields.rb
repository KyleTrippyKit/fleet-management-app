class AddPreCheckAndPartsRequestFields < ActiveRecord::Migration[8.1]
  def change
    # Add pre-check fields to inspection_jobs
    add_column :inspection_jobs, :pre_check_notes, :text unless column_exists?(:inspection_jobs, :pre_check_notes)
    add_column :inspection_jobs, :pre_check_completed_at, :datetime unless column_exists?(:inspection_jobs, :pre_check_completed_at)
    add_column :inspection_jobs, :pre_check_by_id, :bigint unless column_exists?(:inspection_jobs, :pre_check_by_id)
    add_column :inspection_jobs, :additional_findings, :jsonb, default: [] unless column_exists?(:inspection_jobs, :additional_findings)
    
    # Update status check constraint for inspection_jobs
    # Remove old constraint if it exists
    if check_constraint_exists?(:inspection_jobs, name: "job_status_check_v1")
      remove_check_constraint :inspection_jobs, name: "job_status_check_v1"
    end
    
    if check_constraint_exists?(:inspection_jobs, name: "job_status_check_v2")
      remove_check_constraint :inspection_jobs, name: "job_status_check_v2"
    end
    
    add_check_constraint :inspection_jobs, 
      "status IN ('pending_supervisor_review', 'approved', 'assigned', 'pre_check_in_progress', 'pre_check_completed', 'pending_approval', 'in_progress', 'blocked', 'completed', 'cancelled')",
      name: "job_status_check_v2"
    
    # Add ONLY the missing approval fields to parts_requests
    # Note: approved_at, rejected_at, and rejection_reason already exist
    add_column :parts_requests, :approved_by_id, :bigint unless column_exists?(:parts_requests, :approved_by_id)
    add_column :parts_requests, :rejected_by_id, :bigint unless column_exists?(:parts_requests, :rejected_by_id)
    add_column :parts_requests, :issued_by_id, :bigint unless column_exists?(:parts_requests, :issued_by_id)
    add_column :parts_requests, :issued_at, :datetime unless column_exists?(:parts_requests, :issued_at)
    
    # Add foreign keys only if they don't exist
    unless foreign_key_exists?(:parts_requests, :users, column: :approved_by_id)
      add_foreign_key :parts_requests, :users, column: :approved_by_id
    end
    
    unless foreign_key_exists?(:parts_requests, :users, column: :rejected_by_id)
      add_foreign_key :parts_requests, :users, column: :rejected_by_id
    end
    
    unless foreign_key_exists?(:parts_requests, :users, column: :issued_by_id)
      add_foreign_key :parts_requests, :users, column: :issued_by_id
    end
    
    # Add indexes if they don't exist
    unless index_exists?(:parts_requests, :status)
      add_index :parts_requests, :status
    end
    
    unless index_exists?(:parts_requests, [:inspection_job_id, :status])
      add_index :parts_requests, [:inspection_job_id, :status]
    end
  end
  
  private
  
  def column_exists?(table, column)
    connection.column_exists?(table, column)
  end
  
  def check_constraint_exists?(table, name:)
    connection.check_constraints(table).any? { |cc| cc.name == name.to_s }
  end
  
  def foreign_key_exists?(from_table, to_table, column:)
    connection.foreign_keys(from_table).any? do |fk|
      fk.column == column.to_s && fk.to_table == to_table.to_s
    end
  end
  
  def index_exists?(table, columns, name: nil)
    connection.index_exists?(table, columns, name: name)
  end
end