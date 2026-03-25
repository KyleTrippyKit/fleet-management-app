# db/migrate/20260326000000_add_priority_to_findings.rb
class AddPriorityToFindings < ActiveRecord::Migration[8.1]
  def change
    add_column :findings, :priority, :string, default: 'normal'
    add_index :findings, :priority
  end
end