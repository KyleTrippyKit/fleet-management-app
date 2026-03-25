class AddMissingColumnsToInspections < ActiveRecord::Migration[8.1]
  def change
    add_column :inspections, :qc_completed_at, :datetime
    add_column :inspections, :payment_due_at, :datetime
  end
end
