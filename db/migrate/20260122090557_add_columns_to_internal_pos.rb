# db/migrate/YYYYMMDDHHMMSS_add_columns_to_internal_pos.rb
class AddColumnsToInternalPos < ActiveRecord::Migration[8.1]
  def change
    add_column :internal_pos, :work_order_number, :string
    add_column :internal_pos, :purchase_order_id, :bigint
    add_column :internal_pos, :vehicle_id, :bigint
    add_column :internal_pos, :assigned_to_id, :bigint
    add_column :internal_pos, :created_by_id, :bigint
    add_column :internal_pos, :status, :string, default: 'pending'
    add_column :internal_pos, :priority, :string, default: 'normal'
    add_column :internal_pos, :estimated_completion_date, :date
    add_column :internal_pos, :started_at, :datetime
    add_column :internal_pos, :completed_at, :datetime
    add_column :internal_pos, :notes, :text
    
    add_index :internal_pos, :work_order_number, unique: true
    add_index :internal_pos, :purchase_order_id
    add_index :internal_pos, :vehicle_id
    add_index :internal_pos, :assigned_to_id
    add_index :internal_pos, :created_by_id
  end
end