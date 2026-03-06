# db/migrate/20260306140100_add_condition_status_to_reception_logs.rb
class AddConditionStatusToReceptionLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :reception_logs, :condition_status, :string, default: 'pending'
  end
end