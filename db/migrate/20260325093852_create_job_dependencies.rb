class CreateJobDependencies < ActiveRecord::Migration[8.1]
  def change
    create_table :job_dependencies do |t|
      t.bigint :job_id, null: false
      t.bigint :depends_on_job_id, null: false
      t.string :dependency_type, default: 'required' # required, optional, alternative
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end
    
    add_index :job_dependencies, [:job_id, :depends_on_job_id], unique: true
    add_foreign_key :job_dependencies, :inspection_jobs, column: :job_id
    add_foreign_key :job_dependencies, :inspection_jobs, column: :depends_on_job_id
  end
end