# db/migrate/[timestamp]_add_audit_fields_to_access_logs.rb
class AddAuditFieldsToAccessLogs < ActiveRecord::Migration[8.1]
  def change
    # Only add columns if they don't exist
    add_column :access_logs, :action, :string unless column_exists?(:access_logs, :action)
    add_column :access_logs, :resource_type, :string unless column_exists?(:access_logs, :resource_type)
    add_column :access_logs, :resource_id, :integer unless column_exists?(:access_logs, :resource_id)
    add_column :access_logs, :details, :text unless column_exists?(:access_logs, :details)
    add_column :access_logs, :ip_address, :string unless column_exists?(:access_logs, :ip_address)
    add_column :access_logs, :user_agent, :string unless column_exists?(:access_logs, :user_agent)
  end
end