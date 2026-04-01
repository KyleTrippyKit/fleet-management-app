# db/migrate/[TIMESTAMP]_add_diagnosis_completed_at_to_inspections.rb
class AddDiagnosisCompletedAtToInspections < ActiveRecord::Migration[8.1]
  def change
    add_column :inspections, :diagnosis_completed_at, :datetime
    add_index :inspections, :diagnosis_completed_at
  end
end