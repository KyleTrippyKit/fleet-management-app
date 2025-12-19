puts "=== RESTORING DATA ==="

user = User.find_by(email: 'kylerigsby10@yahoo.com')
puts "User: #{user.email} (ID: #{user.id})"

# 1. Assign all vehicles to user
if defined?(Vehicle)
  vehicles = Vehicle.all
  puts "Found #{vehicles.count} vehicles"
  
  vehicles_assigned = 0
  vehicles.each do |vehicle|
    if vehicle.user_id != user.id
      vehicle.update(user_id: user.id)
      vehicles_assigned += 1
      puts "  Assigned: #{vehicle.registration_number || 'Vehicle'} to #{user.email}"
    end
  end
  puts "Assigned #{vehicles_assigned} vehicles to user"
end

# 2. Assign all trips to user
if defined?(Trip) && Trip.column_names.include?('user_id')
  trips = Trip.all
  puts "Found #{trips.count} trips"
  
  trips_assigned = 0
  trips.each do |trip|
    if trip.user_id != user.id
      trip.update(user_id: user.id)
      trips_assigned += 1
    end
  end
  puts "Assigned #{trips_assigned} trips to user"
end

# 3. Assign all drivers to user
if defined?(Driver) && Driver.column_names.include?('user_id')
  drivers = Driver.all
  puts "Found #{drivers.count} drivers"
  
  drivers_assigned = 0
  drivers.each do |driver|
    if driver.user_id != user.id
      driver.update(user_id: user.id)
      drivers_assigned += 1
      puts "  Assigned: #{driver.name} to #{user.email}"
    end
  end
  puts "Assigned #{drivers_assigned} drivers to user"
end

# 4. Check for pictures
puts "\n=== CHECKING PICTURES ==="
if defined?(Vehicle)
  user.vehicles.each do |vehicle|
    puts "Vehicle: #{vehicle.registration_number || 'Unnamed'} (ID: #{vehicle.id})"
    
    # Check different attachment methods
    if vehicle.respond_to?(:images) && vehicle.images.attached?
      puts "  ✅ Has #{vehicle.images.count} image(s)"
      vehicle.images.each_with_index do |image, i|
        puts "    Image #{i+1}: #{image.filename}"
      end
    elsif vehicle.respond_to?(:picture) && vehicle.picture.attached?
      puts "  ✅ Has picture: #{vehicle.picture.filename}"
    elsif vehicle.respond_to?(:photo) && vehicle.photo.attached?
      puts "  ✅ Has photo: #{vehicle.photo.filename}"
    else
      puts "  ❌ No pictures attached"
      
      # Check Active Storage directly
      if ActiveRecord::Base.connection.table_exists?('active_storage_attachments')
        attachments = ActiveRecord::Base.connection.execute(
          "SELECT name FROM active_storage_attachments WHERE record_type = 'Vehicle' AND record_id = #{vehicle.id}"
        ).to_a
        
        if attachments.any?
          puts "  ⚠️  Found #{attachments.count} attachments in database but not accessible via model"
          attachments.each do |a|
            puts "    Attachment name: #{a['name'] || a[0]}"
          end
        end
      end
    end
  end
end

# 5. Check Active Storage attachments
puts "\n=== ACTIVE STORAGE STATUS ==="
if ActiveRecord::Base.connection.table_exists?('active_storage_attachments')
  total = ActiveRecord::Base.connection.execute(
    "SELECT COUNT(*) FROM active_storage_attachments"
  ).first[0]
  
  vehicle_attachments = ActiveRecord::Base.connection.execute(
    "SELECT COUNT(*) FROM active_storage_attachments WHERE record_type = 'Vehicle'"
  ).first[0]
  
  puts "Total attachments: #{total}"
  puts "Vehicle attachments: #{vehicle_attachments}"
  
  if vehicle_attachments > 0
    puts "\nVehicle attachments details:"
    attachments = ActiveRecord::Base.connection.execute(
      "SELECT record_id, name FROM active_storage_attachments WHERE record_type = 'Vehicle'"
    ).to_a
    
    attachments.each do |attachment|
      vehicle_id = attachment['record_id'] || attachment[0]
      name = attachment['name'] || attachment[1]
      vehicle = Vehicle.find_by(id: vehicle_id)
      
      if vehicle
        puts "  Vehicle ID #{vehicle_id}: #{vehicle.registration_number || 'Unnamed'} - #{name}"
      else
        puts "  ⚠️  Vehicle ID #{vehicle_id}: Vehicle not found - #{name}"
      end
    end
  end
end

puts "\n=== SUMMARY ==="
puts "User #{user.email} now has:"
puts "  Vehicles: #{user.vehicles.count}" if user.respond_to?(:vehicles)
puts "  Trips: #{user.trips.count}" if user.respond_to?(:trips)
puts "  Drivers: #{user.drivers.count}" if user.respond_to?(:drivers)
puts "  Maintenance: #{user.maintenances.count}" if user.respond_to?(:maintenances)
