# db/migrate/20260306140000_add_condition_report_id_to_reception_logs.rb
class AddConditionReportIdToReceptionLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :reception_logs, :condition_report_id, :bigint
    add_foreign_key :reception_logs, :vehicle_condition_reports, column: :condition_report_id
    add_index :reception_logs, :condition_report_id
  end
end