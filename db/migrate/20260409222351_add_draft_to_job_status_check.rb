# db/migrate/20260409223000_add_draft_to_job_status_check.rb
class AddDraftToJobStatusCheck < ActiveRecord::Migration[8.1]
  def up
    execute <<-SQL
      ALTER TABLE inspection_jobs 
      DROP CONSTRAINT IF EXISTS job_status_check_v2;
      
      ALTER TABLE inspection_jobs 
      ADD CONSTRAINT job_status_check_v2 
      CHECK (status::text = ANY (ARRAY[
        'draft'::character varying,
        'pending_supervisor_review'::character varying,
        'approved'::character varying,
        'assigned'::character varying,
        'pre_check_in_progress'::character varying,
        'pre_check_completed'::character varying,
        'pending_approval'::character varying,
        'in_progress'::character varying,
        'blocked'::character varying,
        'completed'::character varying,
        'cancelled'::character varying
      ]::text[]));
    SQL
  end

  def down
    execute <<-SQL
      ALTER TABLE inspection_jobs 
      DROP CONSTRAINT IF EXISTS job_status_check_v2;
      
      ALTER TABLE inspection_jobs 
      ADD CONSTRAINT job_status_check_v2 
      CHECK (status::text = ANY (ARRAY[
        'pending_supervisor_review'::character varying,
        'approved'::character varying,
        'assigned'::character varying,
        'pre_check_in_progress'::character varying,
        'pre_check_completed'::character varying,
        'pending_approval'::character varying,
        'in_progress'::character varying,
        'blocked'::character varying,
        'completed'::character varying,
        'cancelled'::character varying
      ]::text[]));
    SQL
  end
end