# db/migrate/20260328000002_add_status_to_findings.rb
class AddStatusToFindings < ActiveRecord::Migration[8.1]
  def change
    add_column :findings, :status, :string, default: 'pending'
    add_index :findings, :status
  end
end