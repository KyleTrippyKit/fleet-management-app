class AddQcColumnsToInspectionJobs < ActiveRecord::Migration[7.0]
  def change
    # Only add columns if they don't already exist
    unless column_exists?(:inspection_jobs, :qc_passed_at)
      add_column :inspection_jobs, :qc_passed_at, :datetime
    end
    
    unless column_exists?(:inspection_jobs, :qc_passed_by_id)
      add_column :inspection_jobs, :qc_passed_by_id, :integer
    end
    
    unless column_exists?(:inspection_jobs, :qc_notes)
      add_column :inspection_jobs, :qc_notes, :text
    end
    
    unless column_exists?(:inspection_jobs, :qc_failed_at)
      add_column :inspection_jobs, :qc_failed_at, :datetime
    end
    
    unless column_exists?(:inspection_jobs, :qc_failure_reason)
      add_column :inspection_jobs, :qc_failure_reason, :text
    end
    
    # Add indexes
    unless index_exists?(:inspection_jobs, :qc_passed_at)
      add_index :inspection_jobs, :qc_passed_at
    end
    
    unless index_exists?(:inspection_jobs, :qc_failed_at)
      add_index :inspection_jobs, :qc_failed_at
    end
  end
end