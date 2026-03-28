# db/migrate/20260327151410_create_work_order_core.rb
class CreateWorkOrderCore < ActiveRecord::Migration[8.1]
  def change
    # 1. Create work_orders table
    create_table :work_orders do |t|
      t.references :vehicle, null: false, foreign_key: true
      t.references :customer, polymorphic: true
      t.string :work_order_number, null: false
      t.string :status, null: false, default: 'received'
      t.string :payment_status, default: 'pending'
      t.decimal :total_amount, precision: 10, scale: 2, default: 0
      t.decimal :paid_amount, precision: 10, scale: 2, default: 0
      t.datetime :received_at, null: false
      t.datetime :inspected_at
      t.datetime :approved_at
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :ready_for_pickup_at
      t.datetime :picked_up_at
      t.string :pickup_code
      t.text :customer_notes
      t.text :internal_notes
      t.jsonb :metadata, default: {}
      t.string :idempotency_key
      t.integer :lock_version, default: 0, null: false
      t.timestamps
    end

    add_index :work_orders, :work_order_number, unique: true
    add_index :work_orders, :status
    add_index :work_orders, [:vehicle_id, :status]
    add_index :work_orders, :idempotency_key, unique: true, where: "idempotency_key IS NOT NULL"

    # 2. Create job_tasks table
    create_table :job_tasks do |t|
      t.references :inspection_job, null: false, foreign_key: true
      t.references :assigned_mechanic, foreign_key: { to_table: :users }
      t.references :finding, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.integer :position, default: 0
      t.string :status, default: 'pending'
      t.decimal :estimated_hours, precision: 5, scale: 2
      t.decimal :actual_hours, precision: 5, scale: 2
      t.decimal :estimated_cost, precision: 10, scale: 2
      t.decimal :actual_cost, precision: 10, scale: 2
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :blocked_at
      t.text :blocked_reason
      t.string :idempotency_key
      t.integer :lock_version, default: 0, null: false
      t.timestamps
    end

    add_index :job_tasks, [:inspection_job_id, :position]
    add_index :job_tasks, :status
    # Use a different name for the index to avoid conflict
    add_index :job_tasks, :assigned_mechanic_id, name: "idx_job_tasks_on_assigned_mechanic"
    add_index :job_tasks, :idempotency_key, unique: true, where: "idempotency_key IS NOT NULL"

    # 3. Create work_sessions table
    create_table :work_sessions do |t|
      t.references :job_task, null: false, foreign_key: true
      t.references :mechanic, null: false, foreign_key: { to_table: :users }
      t.references :updated_by, foreign_key: { to_table: :users }
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.decimal :duration_hours, precision: 5, scale: 2
      t.string :session_type, default: 'work'
      t.text :notes
      t.boolean :system_generated, default: false
      t.string :idempotency_key
      t.integer :lock_version, default: 0, null: false
      t.timestamps
    end

    add_index :work_sessions, [:job_task_id, :started_at]
    add_index :work_sessions, [:mechanic_id, :started_at]
    add_index :work_sessions, :idempotency_key, unique: true, where: "idempotency_key IS NOT NULL"
    
    add_index :work_sessions,
              :mechanic_id,
              unique: true,
              where: "ended_at IS NULL",
              name: "index_one_active_session_per_mechanic"
  end
end