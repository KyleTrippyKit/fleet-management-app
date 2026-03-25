# db/migrate/20260326000000_add_supervisor_and_audit_fields.rb
class AddSupervisorAndAuditFields < ActiveRecord::Migration[8.1]
  def change
    # 1. Add supervisor to inspections (with check)
    unless column_exists?(:inspections, :supervisor_id)
      add_reference :inspections, :supervisor, foreign_key: { to_table: :users }, null: true
    end
    
    # 2. Add audit fields to inspections (with checks)
    unless column_exists?(:inspections, :created_by_id)
      add_column :inspections, :created_by_id, :bigint
      add_foreign_key :inspections, :users, column: :created_by_id
    end
    
    unless column_exists?(:inspections, :updated_by_id)
      add_column :inspections, :updated_by_id, :bigint
      add_foreign_key :inspections, :users, column: :updated_by_id
    end
    
    # 3. Add audit fields to inspection_jobs (with checks)
    unless column_exists?(:inspection_jobs, :created_by_id)
      add_column :inspection_jobs, :created_by_id, :bigint
      add_foreign_key :inspection_jobs, :users, column: :created_by_id
    end
    
    unless column_exists?(:inspection_jobs, :updated_by_id)
      add_column :inspection_jobs, :updated_by_id, :bigint
      add_foreign_key :inspection_jobs, :users, column: :updated_by_id
    end
    
    # 4. Add audit fields to quotations (with checks)
    unless column_exists?(:quotations, :created_by_id)
      add_column :quotations, :created_by_id, :bigint
      add_foreign_key :quotations, :users, column: :created_by_id
    end
    
    unless column_exists?(:quotations, :updated_by_id)
      add_column :quotations, :updated_by_id, :bigint
      add_foreign_key :quotations, :users, column: :updated_by_id
    end
    
    # 5. Add job tracking fields to findings (with checks)
    unless column_exists?(:findings, :job_created)
      add_column :findings, :job_created, :boolean, default: false
    end
    
    unless column_exists?(:findings, :job_id)
      add_column :findings, :job_id, :bigint
      add_foreign_key :findings, :inspection_jobs, column: :job_id
    end
    
    # 6. Add indexes for better performance
    add_index :inspections, :supervisor_id unless index_exists?(:inspections, :supervisor_id)
    add_index :inspections, :created_by_id unless index_exists?(:inspections, :created_by_id)
    add_index :inspections, :updated_by_id unless index_exists?(:inspections, :updated_by_id)
    add_index :inspection_jobs, :created_by_id unless index_exists?(:inspection_jobs, :created_by_id)
    add_index :inspection_jobs, :updated_by_id unless index_exists?(:inspection_jobs, :updated_by_id)
    add_index :quotations, :created_by_id unless index_exists?(:quotations, :created_by_id)
    add_index :quotations, :updated_by_id unless index_exists?(:quotations, :updated_by_id)
    add_index :findings, :job_id unless index_exists?(:findings, :job_id)
  end
end