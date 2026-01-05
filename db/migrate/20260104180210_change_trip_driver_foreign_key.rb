class ChangeTripDriverForeignKey < ActiveRecord::Migration[8.1]
  def change
    # First check if foreign key exists and remove it
    foreign_keys = ActiveRecord::Base.connection.foreign_keys('trips')
    driver_fk = foreign_keys.find { |fk| fk.column == 'driver_id' }
    
    if driver_fk
      remove_foreign_key :trips, name: driver_fk.name
    end
    
    # Add new foreign key to drivers table
    add_foreign_key :trips, :drivers, column: :driver_id
  end
end
