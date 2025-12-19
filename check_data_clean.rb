puts "=== CHECKING DATA ==="

# Current user
user = User.find_by(email: 'kylerigsby10@yahoo.com')
puts "User: #{user.email} (ID: #{user.id})"

# Check models
puts "\n=== DATA COUNTS ==="
begin
  puts "Vehicles: #{Vehicle.count}"
  Vehicle.all.each do |v|
    puts "  - #{v.registration_number || 'No reg'} (ID: #{v.id})"
    puts "    User ID: #{v.user_id}" if v.respond_to?(:user_id)
  end
rescue => e
  puts "Error checking vehicles: #{e.message}"
end

begin
  puts "Maintenance: #{Maintenance.count}"
rescue => e
  puts "Error checking maintenance: #{e.message}"
end

begin
  puts "Trips: #{Trip.count}"
  Trip.limit(3).each do |t|
    puts "  - ID: #{t.id}, Vehicle ID: #{t.vehicle_id}" if t.respond_to?(:vehicle_id)
  end
rescue => e
  puts "Error checking trips: #{e.message}"
end

begin
  puts "Drivers: #{Driver.count}"
  Driver.all.each do |d|
    puts "  - #{d.name} (ID: #{d.id})"
  end
rescue => e
  puts "Error checking drivers: #{e.message}"
end

begin
  puts "VehicleUsage: #{VehicleUsage.count}"
rescue => e
  puts "Error checking vehicle usage: #{e.message}"
end

# Check Active Storage
puts "\n=== ACTIVE STORAGE ==="
begin
  if ActiveRecord::Base.connection.table_exists?('active_storage_attachments')
    result = ActiveRecord::Base.connection.execute("SELECT COUNT(*) as count FROM active_storage_attachments")
    count = result.first['count'] rescue result.first[0]
    puts "Attachments: #{count}"
    
    if count.to_i > 0
      # Check what's attached
      attachments = ActiveRecord::Base.connection.execute(
        "SELECT record_type, record_id, name FROM active_storage_attachments LIMIT 5"
      ).to_a
      
      puts "Sample attachments:"
      attachments.each do |a|
        puts "  #{a['record_type']} ID #{a['record_id']}: #{a['name']}"
        
        # If it's a vehicle, show details
        if a['record_type'] == 'Vehicle'
          v = Vehicle.find_by(id: a['record_id'])
          puts "    Vehicle: #{v.registration_number if v}"
        end
      end
    end
  else
    puts "Active Storage not configured"
  end
rescue => e
  puts "Error checking Active Storage: #{e.message}"
end

# Check user ownership
puts "\n=== USER OWNERSHIP ==="
if user
  puts "User #{user.email} owns:"
  
  if user.respond_to?(:vehicles)
    puts "  Vehicles: #{user.vehicles.count}"
    user.vehicles.each do |v|
      puts "    - #{v.registration_number || 'Unnamed'} (ID: #{v.id})"
      
      # Check for pictures
      if v.respond_to?(:images) && v.images.attached?
        puts "      Images: #{v.images.count} attached"
      elsif v.respond_to?(:picture) && v.picture.attached?
        puts "      Has picture"
      else
        puts "      No pictures"
      end
    end
  end
  
  if user.respond_to?(:trips)
    puts "  Trips: #{user.trips.count}"
  end
  
  if user.respond_to?(:drivers)
    puts "  Drivers: #{user.drivers.count}"
  end
  
  if user.respond_to?(:maintenances)
    puts "  Maintenance: #{user.maintenances.count}"
  end
end

# Check for orphaned data
puts "\n=== ORPHANED DATA ==="
begin
  # Vehicles without user
  orphaned_vehicles = Vehicle.where(user_id: nil).or(Vehicle.where.not(user_id: User.pluck(:id)))
  puts "Orphaned vehicles: #{orphaned_vehicles.count}"
  
  # Trips without user
  if Trip.column_names.include?('user_id')
    orphaned_trips = Trip.where(user_id: nil).or(Trip.where.not(user_id: User.pluck(:id)))
    puts "Orphaned trips: #{orphaned_trips.count}"
  end
rescue => e
  puts "Error checking orphaned data: #{e.message}"
end
