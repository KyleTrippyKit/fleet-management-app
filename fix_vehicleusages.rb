require 'csv'

if File.exist?('vehicleusages_export.csv')
  # Try both possible class names
  model_class = defined?(VehicleUsage) ? VehicleUsage : 
                (defined?(Vehicleusage) ? Vehicleusage : nil)
  
  if model_class
    csv = CSV.read('vehicleusages_export.csv', headers: true)
    
    csv.each do |row|
      attrs = row.to_hash.except('id')
      
      # Find driver
      if attrs['driver_id']
        driver = Driver.find_by(id: attrs['driver_id']) || Driver.first
        attrs['driver_id'] = driver.id if driver
      end
      
      # Find vehicle
      if attrs['vehicle_id']
        vehicle = Vehicle.find_by(id: attrs['vehicle_id']) || Vehicle.first
        attrs['vehicle_id'] = vehicle.id if vehicle
      end
      
      model_class.create!(attrs)
    end
    puts "Imported #{csv.count} vehicle usages"
  else
    puts "No VehicleUsage model found"
  end
end
