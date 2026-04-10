class AddPartTypeToInspectionJobParts < ActiveRecord::Migration[8.1]
  def change
    add_column :inspection_job_parts, :part_type, :string, default: 'required'
    add_column :inspection_job_parts, :cannot_complete_without, :boolean, default: false
    
    add_index :inspection_job_parts, :part_type
    add_index :inspection_job_parts, :cannot_complete_without
    
    # Update existing records to have part_type = 'required' by default
    execute <<-SQL
      UPDATE inspection_job_parts SET part_type = 'required' WHERE part_type IS NULL;
    SQL
  end
end