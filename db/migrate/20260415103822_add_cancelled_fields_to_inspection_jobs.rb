# db/migrate/20260416000001_add_cancelled_fields_to_inspection_jobs.rb
class AddCancelledFieldsToInspectionJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :inspection_jobs, :cancelled_at, :datetime unless column_exists?(:inspection_jobs, :cancelled_at)
    add_column :inspection_jobs, :cancelled_by_id, :integer unless column_exists?(:inspection_jobs, :cancelled_by_id)
    add_column :inspection_jobs, :cancellation_reason, :text unless column_exists?(:inspection_jobs, :cancellation_reason)
  end
end