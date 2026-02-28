# db/migrate/xxxxxx_create_inspection_jobs.rb
class CreateInspectionJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :inspection_jobs do |t|
      t.references :inspection, null: false, foreign_key: true
      t.references :job_template, foreign_key: true
      t.references :assigned_mechanic, foreign_key: { to_table: :users }
      t.text :description, null: false
      t.decimal :estimated_labor_cost, precision: 10, scale: 2
      t.decimal :estimated_parts_cost, precision: 10, scale: 2
      t.string :priority
      t.datetime :completed_at
      t.text :notes

      t.timestamps
    end
  end
end