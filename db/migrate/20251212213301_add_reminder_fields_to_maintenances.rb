class AddReminderFieldsToMaintenances < ActiveRecord::Migration[8.1]
  def up
    add_column :maintenances, :next_due_date, :date
    add_column :maintenances, :reminder_sent_at, :datetime

    Maintenance.reset_column_information

    say_with_time "Backfilling next_due_date for maintenances" do
      Maintenance
        .where(next_due_date: nil)
        .where.not(end_date: nil)
        .find_each do |maintenance|

        maintenance.update_columns(
          next_due_date: maintenance.end_date + 6.months
        )
      end
    end
  end

  def down
    remove_column :maintenances, :next_due_date
    remove_column :maintenances, :reminder_sent_at
  end
end
