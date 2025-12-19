require 'csv'

puts "🔄 FIXING ALL IMPORTS WITH CORRECT MODEL NAMES"

# 1. FIX USERS (MOST IMPORTANT FOR LOGIN)
if File.exist?('users_export.csv')
  puts "1. Fixing users..."
  # Clear existing but keep your current login
  User.where.not(email: 'kylerigsby10@yahoo.com').destroy_all
  
  CSV.read('users_export.csv', headers: true).each do |row|
    attrs = row.to_hash.except('id')
    
    # Skip if already exists
    next if User.exists?(email: attrs['email'])
    
    # Create with original encrypted password
    user = User.new(
      email: attrs['email'],
      encrypted_password: attrs['encrypted_password'],
      created_at: attrs['created_at'],
      updated_at: attrs['updated_at']
    )
    user.save!(validate: false)
    puts "  Imported: #{user.email}"
  end
  puts "✅ Users: #{User.count}"
end

# 2. FIX TRIPS (needs driver_id, vehicle_id)
if File.exist?('trips_export.csv')
  puts "2. Fixing trips..."
  Trip.destroy_all
  
  CSV.read('trips_export.csv', headers: true).each do |row|
    attrs = row.to_hash.except('id')
    
    # Use existing driver/vehicle or first available
    driver = Driver.find_by(id: attrs['driver_id']) || Driver.first
    vehicle = Vehicle.find_by(id: attrs['vehicle_id']) || Vehicle.first
    
    if driver && vehicle
      Trip.create!(
        driver_id: driver.id,
        vehicle_id: vehicle.id,
        start_time: attrs['start_time'],
        end_time: attrs['end_time'],
        created_at: attrs['created_at'],
        updated_at: attrs['updated_at']
      )
    end
  end
  puts "✅ Trips: #{Trip.count}"
end

# 3. FIX MAINTENANCES (needs vehicle_id, service_provider_id)
if File.exist?('maintenances_export.csv')
  puts "3. Fixing maintenances..."
  Maintenance.destroy_all
  
  # Get first service_provider
  service_provider = ServiceProvider.first
  
  CSV.read('maintenances_export.csv', headers: true).each do |row|
    attrs = row.to_hash.except('id')
    
    vehicle = Vehicle.find_by(id: attrs['vehicle_id']) || Vehicle.first
    
    if vehicle && service_provider
      Maintenance.create!(
        vehicle_id: vehicle.id,
        service_provider_id: service_provider.id,
        date: attrs['date'],
        mileage: attrs['mileage'],
        work_performed: attrs['work_performed'],
        cost: attrs['cost'],
        status: attrs['status'],
        created_at: attrs['created_at'],
        updated_at: attrs['updated_at']
      )
    end
  end
  puts "✅ Maintenances: #{Maintenance.count}"
end

# 4. FIX VEHICLE_USAGES (needs driver_id, vehicle_id)
if File.exist?('vehicleusages_export.csv')
  puts "4. Fixing vehicle_usages..."
  VehicleUsage.destroy_all
  
  CSV.read('vehicleusages_export.csv', headers: true).each do |row|
    attrs = row.to_hash.except('id')
    
    driver = Driver.find_by(id: attrs['driver_id']) || Driver.first
    vehicle = Vehicle.find_by(id: attrs['vehicle_id']) || Vehicle.first
    
    if driver && vehicle
      VehicleUsage.create!(
        driver_id: driver.id,
        vehicle_id: vehicle.id,
        start_date: attrs['start_date'],
        end_date: attrs['end_date'],
        purpose: attrs['purpose'],
        created_at: attrs['created_at'],
        updated_at: attrs['updated_at']
      )
    end
  end
  puts "✅ VehicleUsages: #{VehicleUsage.count}"
end

puts "\n🎉 ALL IMPORTS FIXED!"
puts "Run 'rails runner \"puts User.pluck(:email)\"' to see available logins"
