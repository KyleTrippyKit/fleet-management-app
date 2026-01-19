# db/migrate/YYYYMMDDHHMMSS_add_audit_columns_to_pos_transactions.rb
class AddAuditColumnsToPosTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :pos_transactions, :voided_at, :datetime
    add_column :pos_transactions, :voided_by, :bigint
    add_column :pos_transactions, :refunded_at, :datetime
    add_column :pos_transactions, :refunded_by, :bigint
    add_column :pos_transactions, :archived, :boolean, default: false
    add_column :pos_transactions, :archived_at, :datetime
    add_column :pos_transactions, :archived_by, :bigint
    add_column :pos_transactions, :archive_reason, :text
    
    # Add foreign key constraints
    add_foreign_key :pos_transactions, :users, column: :voided_by
    add_foreign_key :pos_transactions, :users, column: :refunded_by
    add_foreign_key :pos_transactions, :users, column: :archived_by
  end
end