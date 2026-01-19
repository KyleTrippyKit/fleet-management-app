# db/migrate/[timestamp]_add_missing_columns_to_cashier_sessions.rb
class AddMissingColumnsToCashierSessions < ActiveRecord::Migration[8.1]
  def change
    # Add foreign key references
    add_reference :cashier_sessions, :agency, foreign_key: true
    add_reference :cashier_sessions, :user, foreign_key: true
    add_reference :cashier_sessions, :closed_by, foreign_key: { to_table: :users }
    
    # Add status column (already exists but make sure it's correct)
    change_column :cashier_sessions, :status, :integer, default: 0, null: false
    
    # Add financial columns
    add_column :cashier_sessions, :starting_cash, :decimal, precision: 10, scale: 2, default: 0.0
    add_column :cashier_sessions, :ending_cash, :decimal, precision: 10, scale: 2
    add_column :cashier_sessions, :total_sales, :decimal, precision: 10, scale: 2, default: 0.0
    add_column :cashier_sessions, :cash_total, :decimal, precision: 10, scale: 2, default: 0.0
    add_column :cashier_sessions, :card_total, :decimal, precision: 10, scale: 2, default: 0.0
    add_column :cashier_sessions, :voided_total, :decimal, precision: 10, scale: 2, default: 0.0
    add_column :cashier_sessions, :refunded_total, :decimal, precision: 10, scale: 2, default: 0.0
    
    # Add count columns
    add_column :cashier_sessions, :transaction_count, :integer, default: 0
    add_column :cashier_sessions, :voided_count, :integer, default: 0
    add_column :cashier_sessions, :refunded_count, :integer, default: 0
    
    # Add other columns
    add_column :cashier_sessions, :discrepancy, :decimal, precision: 10, scale: 2
    add_column :cashier_sessions, :notes, :text
    add_column :cashier_sessions, :opened_at, :datetime
    add_column :cashier_sessions, :closed_at, :datetime
    
    # Add indexes
    add_index :cashier_sessions, [:agency_id, :status]
    add_index :cashier_sessions, [:user_id, :status]
    add_index :cashier_sessions, [:opened_at, :closed_at]
  end
end