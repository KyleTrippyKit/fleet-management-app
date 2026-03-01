# db/migrate/20260301000002_add_part_links_to_inspection_jobs.rb
class AddPartLinksToInspectionJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :inspection_jobs, :requires_part_approval, :boolean, default: false
    add_column :inspection_jobs, :parts_approved, :boolean, default: false
    add_column :inspection_jobs, :parts_approval_notes, :text
    
    create_table :inspection_job_parts do |t|
      t.references :inspection_job, null: false, foreign_key: true
      t.references :part, null: false, foreign_key: true
      t.integer :quantity, default: 1
      t.decimal :estimated_cost, precision: 10, scale: 2
      t.decimal :actual_cost, precision: 10, scale: 2
      t.boolean :customer_approved, default: false
      t.datetime :customer_approved_at
      t.text :notes
      t.timestamps
    end
    
    add_index :inspection_job_parts, [:inspection_job_id, :part_id], unique: true, name: 'idx_inspection_job_parts_unique'
  end
end