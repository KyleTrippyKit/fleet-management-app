class RenameChangesToAuditChangesInAuditLogs < ActiveRecord::Migration[8.1]
  def change
    # Rename the column if it exists
    if column_exists?(:audit_logs, :changes)
      rename_column :audit_logs, :changes, :audit_changes
    end
  end
end