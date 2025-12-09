class AddDurationHoursToTrips < ActiveRecord::Migration[8.1]
  def change
    add_column :trips, :duration_hours, :float
  end
end
