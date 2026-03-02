# db/migrate/20260302120000_add_verification_to_inspection_jobs.rb
class AddVerificationToInspectionJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :inspection_jobs, :recommendation_source, :string, default: 'inspector'
    add_column :inspection_jobs, :verification_status, :string, default: 'pending'
    add_column :inspection_jobs, :verified_by_mechanic_id, :integer
    add_column :inspection_jobs, :verified_at, :datetime
    add_column :inspection_jobs, :mechanic_notes, :text
    add_column :inspection_jobs, :parent_job_id, :integer
    add_column :inspection_jobs, :requires_approval, :boolean, default: false
    
    add_index :inspection_jobs, :verification_status
    add_index :inspection_jobs, :verified_by_mechanic_id
    add_index :inspection_jobs, :parent_job_id
  end
end