# db/migrate/20260416000000_update_inspection_job_status_constraint.rb
class UpdateInspectionJobStatusConstraint < ActiveRecord::Migration[8.1]
  def up
    # Drop existing constraint
    execute <<-SQL
      ALTER TABLE inspection_jobs DROP CONSTRAINT IF EXISTS job_status_check_v2;
    SQL
    
    # Add new constraint with all statuses from the model
    execute <<-SQL
      ALTER TABLE inspection_jobs ADD CONSTRAINT job_status_check_v2 CHECK (
        status::text = ANY (ARRAY[
          'draft'::text,
          'pending_supervisor_review'::text,
          'pending_mechanic_review'::text,
          'pending_parts_review'::text,
          'approved'::text,
          'assigned'::text,
          'pre_check_in_progress'::text,
          'pre_check_completed'::text,
          'pending_approval'::text,
          'approved_for_work'::text,
          'pending_mechanic_work'::text,
          'in_progress'::text,
          'paused'::text,
          'blocked'::text,
          'rework_needed'::text,
          'completed'::text,
          'qc_pending'::text,
          'qc_in_progress'::text,
          'qc_passed'::text,
          'qc_failed'::text,
          'cancelled'::text
        ])
      );
    SQL
  end

  def down
    execute <<-SQL
      ALTER TABLE inspection_jobs DROP CONSTRAINT IF EXISTS job_status_check_v2;
    SQL
  end
end