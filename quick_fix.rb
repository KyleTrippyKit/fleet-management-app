puts "=== QUICK FIX FOR VEHICLE DATA ==="

user = User.find_by(email: 'kylerigsby10@yahoo.com')
puts "User: #{user.email} (ID: #{user.id})"

# 1. Assign all orphaned vehicles to current user
if defined?(Vehicle)
  orphaned_vehicles = Vehicle.where(user_id: nil).or(Vehicle.where.not(user_id: User.pluck(:id)))
  puts "Assigning #{orphaned_vehicles.count} orphaned vehicles to #{user.email}..."
  orphaned_vehicles.update_all(user_id: user.id)
end

# 2. Assign all orphaned maintenance records
if defined?(Maintenance)
  orphaned_maintenance = Maintenance.where(user_id: nil).or(Maintenance.where.not(user_id: User.pluck(:id)))
  puts "Assigning #{orphaned_maintenance.count} orphaned maintenance records to #{user.email}..."
  orphaned_maintenance.update_all(user_id: user.id)
end

# 3. Assign all orphaned trips
if defined?(Trip)
  orphaned_trips = Trip.where(user_id: nil).or(Trip.where.not(user_id: User.pluck(:id)))
  puts "Assigning #{orphaned_trips.count} orphaned trips to #{user.email}..."
  orphaned_trips.update_all(user_id: user.id)
end

# 4. Check results
puts "\n=== RESULTS ==="
if defined?(Vehicle)
  puts "Vehicles: #{Vehicle.where(user_id: user.id).count} belong to #{user.email}"
  Vehicle.where(user_id: user.id).each do |v|
    puts "  - #{v.registration_number || 'Unnamed'} (ID: #{v.id})"
  end
end

if defined?(Maintenance)
  puts "Maintenance records: #{Maintenance.where(user_id: user.id).count} belong to #{user.email}"
end

if defined?(Trip)
  puts "Trips: #{Trip.where(user_id: user.id).count} belong to #{user.email}"
end

# 5. Check for pictures
puts "\n=== PICTURES ==="
if defined?(Vehicle)
  vehicles_with_pictures = 0
  Vehicle.where(user_id: user.id).each do |vehicle|
    if vehicle.images.attached?
      puts "✅ #{vehicle.registration_number}: #{vehicle.images.count} image(s)"
      vehicles_with_pictures += 1
    elsif vehicle.respond_to?(:picture) && vehicle.picture.attached?
      puts "✅ #{vehicle.registration_number}: Has picture"
      vehicles_with_pictures += 1
    else
      puts "❌ #{vehicle.registration_number}: No pictures"
    end
  end
  puts "\nTotal vehicles with pictures: #{vehicles_with_pictures}/#{Vehicle.where(user_id: user.id).count}"
end
