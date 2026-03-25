class AddFindingsToInspections < ActiveRecord::Migration[8.1]
  def change
    create_table :findings do |t|
      t.bigint :inspection_id, null: false
      t.bigint :inspection_job_id
      t.string :finding_type # initial, mechanic, final
      t.text :description
      t.string :severity # critical, major, minor
      t.boolean :blocking, default: false
      t.boolean :client_approved, default: false
      t.datetime :client_approved_at
      t.bigint :created_by_id
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end
    
    add_foreign_key :findings, :inspections
    add_foreign_key :findings, :inspection_jobs
    add_foreign_key :findings, :users, column: :created_by_id
    add_index :findings, [:inspection_id, :blocking]
  end
end