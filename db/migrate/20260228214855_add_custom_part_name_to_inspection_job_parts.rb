class AddCustomPartNameToInspectionJobParts < ActiveRecord::Migration[8.1]
  def change
    add_column :inspection_job_parts, :custom_part_name, :string
  end
end
