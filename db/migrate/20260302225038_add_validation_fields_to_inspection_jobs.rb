class AddValidationFieldsToInspectionJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :inspection_jobs, :locked_for_changes, :boolean, default: false
    add_column :inspection_jobs, :locked_at, :datetime
    add_column :inspection_jobs, :quantity_used, :integer, default: 0
  end
end