class AddInspectionJobIdToQuotationJobs < ActiveRecord::Migration[8.1]
  def change
    # Check if column exists first
    unless column_exists?(:quotation_jobs, :inspection_job_id)
      # add_reference automatically creates an index, so we don't need to add it separately
      add_reference :quotation_jobs, :inspection_job, foreign_key: true, null: true
    else
      # If column exists but index doesn't, add index separately
      unless index_exists?(:quotation_jobs, :inspection_job_id)
        add_index :quotation_jobs, :inspection_job_id
      end
    end
  end
end