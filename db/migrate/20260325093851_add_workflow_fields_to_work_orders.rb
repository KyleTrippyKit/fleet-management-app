class AddWorkflowFieldsToWorkOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :inspections, :workflow_type, :string, default: 'work_before_payment'
    add_column :inspections, :client_approval_status, :string, default: 'pending'
    add_column :inspections, :client_selected_jobs, :jsonb, default: {}
    add_column :inspections, :payment_status, :string, default: 'pending'
    add_column :inspections, :pickup_scheduled_at, :datetime
    add_column :inspections, :pickup_code, :string
    add_column :inspections, :storage_fee_days, :integer, default: 0
    
    add_column :quotations, :version_number, :integer, default: 1
    add_column :quotations, :original_quotation_id, :integer
    
    # Add status column to inspection_jobs first
    add_column :inspection_jobs, :status, :string, default: 'pending'
    
    add_column :inspection_jobs, :blocked_reason, :text
    add_column :inspection_jobs, :blocked_at, :datetime
    add_column :inspection_jobs, :unblocked_at, :datetime
    
    add_index :inspections, :pickup_code, unique: true
    add_index :inspection_jobs, :status
  end
end