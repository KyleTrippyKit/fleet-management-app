# db/migrate/20260301000003_create_mechanic_assignments.rb
class CreateMechanicAssignments < ActiveRecord::Migration[8.1]
  def change
    create_table :mechanic_assignments do |t|
      t.references :inspection_job, null: false, foreign_key: true
      t.references :mechanic, null: false, foreign_key: { to_table: :users }
      t.string :status, default: 'assigned'
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :qc_requested_at
      t.datetime :qc_completed_at
      t.text :mechanic_notes
      t.text :qc_notes
      t.timestamps
    end
    
    add_index :mechanic_assignments, [:mechanic_id, :status]
  end
end