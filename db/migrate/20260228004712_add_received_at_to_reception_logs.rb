class AddReceivedAtToReceptionLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :reception_logs, :received_at, :datetime
    add_index :reception_logs, :received_at
    
    # Backfill received_at with check_in_time for existing records
    reversible do |dir|
      dir.up do
        ReceptionLog.reset_column_information
        ReceptionLog.where(received_at: nil).find_each do |log|
          log.update_columns(received_at: log.check_in_time)
        end
      end
    end
  end
end