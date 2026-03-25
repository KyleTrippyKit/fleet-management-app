class AddEstimatedHoursToInspectionJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :inspection_jobs, :estimated_hours, :decimal
  end
end
