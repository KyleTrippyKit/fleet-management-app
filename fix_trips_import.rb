require 'csv'

puts "Fixing trip import..."

if File.exist?('trips_export.csv') && defined?(Trip)
  csv = CSV.read('trips_export.csv', headers: true)
  
  csv.each do |row|
    attrs = row.to_hash.except('id')
    
    # Find vehicle by original ID or first available
    if attrs['vehicle_id']
      vehicle = Vehicle.find_by(id: attrs['vehicle_id']) || Vehicle.first
      attrs['vehicle_id'] = vehicle.id if vehicle
    end
    
    # Find driver by original ID or first available
    if attrs['driver_id']
      driver = Driver.find_by(id: attrs['driver_id']) || Driver.first
      attrs['driver_id'] = driver.id if driver
    end
    
    # Create trip
    Trip.create!(attrs)
    puts "Imported trip: #{attrs['start_time']}"
  end
end

puts "Trips imported: #{Trip.count}"
