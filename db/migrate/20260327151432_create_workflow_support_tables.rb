# db/migrate/20260327151432_create_workflow_support_tables.rb
class CreateWorkflowSupportTables < ActiveRecord::Migration[8.1]
  def change
    create_table :job_task_dependencies do |t|
      t.references :job_task, null: false, foreign_key: true
      t.references :depends_on_task, null: false, foreign_key: { to_table: :job_tasks }

      t.string :dependency_type, default: 'required'
      t.timestamps
    end

    add_index :job_task_dependencies,
              [:job_task_id, :depends_on_task_id],
              unique: true,
              name: "idx_unique_task_dependency"

    create_table :event_outboxes do |t|
      t.string :event_type, null: false
      t.string :aggregate_type, null: false
      t.bigint :aggregate_id, null: false

      t.jsonb :payload, null: false

      t.string :status, default: 'pending'
      t.integer :retry_count, default: 0

      t.datetime :processing_started_at
      t.datetime :processed_at

      t.text :error_message

      t.string :idempotency_key
      t.string :external_id

      t.timestamps
    end

    add_index :event_outboxes, [:status, :created_at]
    add_index :event_outboxes, :idempotency_key, unique: true, where: "idempotency_key IS NOT NULL"
    add_index :event_outboxes, :external_id, unique: true, where: "external_id IS NOT NULL"
  end
end