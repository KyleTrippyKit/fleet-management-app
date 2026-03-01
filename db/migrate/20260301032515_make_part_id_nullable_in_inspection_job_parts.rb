# db/migrate/xxxxxx_make_part_id_nullable_in_inspection_job_parts.rb
class MakePartIdNullableInInspectionJobParts < ActiveRecord::Migration[8.1]
  def change
    change_column_null :inspection_job_parts, :part_id, true
  end
end