# db/migrate/20260308225416_add_more_indexes.rb
class AddMoreIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :reception_logs, [:received_at, :status], if_not_exists: true
    add_index :vehicle_condition_reports, [:vehicle_id, :created_at], if_not_exists: true
    add_index :inspections, [:status, :created_at], if_not_exists: true
    add_index :parts_requests, [:status, :created_at], if_not_exists: true
    add_index :vendor_rfqs, [:status, :created_at], if_not_exists: true
    add_index :invoices, [:status, :due_date], if_not_exists: true
    add_index :purchase_orders, [:status, :created_at], if_not_exists: true
    add_index :notifications, [:user_id, :read, :created_at], if_not_exists: true
  end
end