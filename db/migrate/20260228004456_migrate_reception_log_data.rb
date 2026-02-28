class MigrateReceptionLogData < ActiveRecord::Migration[8.1]
  def up
    ReceptionLog.reset_column_information
    
    ReceptionLog.find_each do |log|
      # Map old fields to new fields
      log.update_columns(
        driver_name: log.visitor_name,
        received_at: log.check_in_time
      )
    end
  end

  def down
    # No need to rollback this data migration
  end
end