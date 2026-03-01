# db/migrate/20260301000004_add_workflow_status_to_purchase_orders.rb
class AddWorkflowStatusToPurchaseOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :purchase_orders, :workflow_status, :string, default: 'pending_parts_coordinator'
    add_column :purchase_orders, :parts_coordinator_id, :bigint
    add_column :purchase_orders, :billing_team_id, :bigint
    add_column :purchase_orders, :finance_approved_at, :datetime
    add_column :purchase_orders, :finance_approved_by_id, :bigint
    
    add_index :purchase_orders, :workflow_status
    add_foreign_key :purchase_orders, :users, column: :parts_coordinator_id
    add_foreign_key :purchase_orders, :users, column: :billing_team_id
    add_foreign_key :purchase_orders, :users, column: :finance_approved_by_id
  end
end