puts "=== COMPLETE FIX FOR ACTIVE PLUS DEMO ==="

user = User.find_by(email: 'kylerigsby10@yahoo.com')
puts "User: #{user.email} (ID: #{user.id})"

# 1. Check and fix driver assignments
puts "\n=== FIXING DRIVER ASSIGNMENTS ==="
if defined?(Driver) && Driver.column_names.include?('user_id')
  # Assign all drivers to current user if they're not assigned
  drivers_to_fix = Driver.where(user_id: nil).or(Driver.where.not(user_id: User.pluck(:id)))
  
  if drivers_to_fix.any?
    puts "Assigning #{drivers_to_fix.count} drivers to #{user.email}..."
    drivers_to_fix.update_all(user_id: user.id)
    puts "✅ Done"
  else
    puts "All drivers are properly assigned"
  end
  
  # Show current assignments
  puts "\nCurrent driver assignments:"
  User.all.each do |u|
    count = Driver.where(user_id: u.id).count
    puts "  #{u.email}: #{count} drivers" if count > 0
  end
end

# 2. Check vehicle pictures
puts "\n=== CHECKING VEHICLE PICTURES ==="
if defined?(Vehicle)
  vehicles_with_pictures = Vehicle.where.not(picture: [nil, ''])
  vehicles_without_pictures = Vehicle.where(picture: [nil, ''])
  
  puts "Vehicles with pictures: #{vehicles_with_pictures.count}/#{Vehicle.count}"
  
  if vehicles_with_pictures.any?
    puts "\nVehicles that have pictures (from 'picture' column):"
    vehicles_with_pictures.each do |vehicle|
      puts "  #{vehicle.registration_number || 'Unnamed'}: #{vehicle.picture}"
    end
  end
  
  if vehicles_without_pictures.any?
    puts "\nVehicles WITHOUT pictures:"
    vehicles_without_pictures.each do |vehicle|
      puts "  #{vehicle.registration_number || 'Unnamed'} (ID: #{vehicle.id})"
    end
  end
end

# 3. Check Active Storage for any attachments
puts "\n=== CHECKING ACTIVE STORAGE ==="
if ActiveRecord::Base.connection.table_exists?('active_storage_attachments')
  total = ActiveRecord::Base.connection.execute(
    "SELECT COUNT(*) FROM active_storage_attachments"
  ).first[0]
  
  puts "Active Storage attachments: #{total}"
  
  if total > 0
    puts "\nActive Storage attachments by type:"
    result = ActiveRecord::Base.connection.execute(
      "SELECT record_type, COUNT(*) FROM active_storage_attachments GROUP BY record_type"
    )
    result.each do |row|
      puts "  #{row[0]}: #{row[1]}"
    end
  else
    puts "⚠️  No Active Storage attachments found"
    puts "   Your app uses the 'picture' column for vehicle images, not Active Storage"
  end
end

# 4. Create maintenance records if needed
puts "\n=== MAINTENANCE RECORDS ==="
if defined?(Maintenance)
  if Maintenance.count == 0
    puts "Creating sample maintenance records..."
    
    # Check if Maintenance has user_id column
    has_user_id = Maintenance.column_names.include?('user_id')
    
    Vehicle.first(3).each do |vehicle|
      maintenance_data = {
        vehicle_id: vehicle.id,
        date: Date.today - rand(30).days,
        description: ["Oil change", "Tire rotation", "Brake inspection", "Filter replacement"].sample,
        cost: rand(50..200),
        mileage: vehicle.mileage ? vehicle.mileage + rand(1000) : rand(5000..20000),
        status: "completed",
        details: "Regular maintenance service"
      }
      
      # Add user_id if column exists
      maintenance_data[:user_id] = user.id if has_user_id
      
      # Check required columns
      required_columns = Maintenance.column_names - ['id', 'created_at', 'updated_at']
      maintenance_data = maintenance_data.slice(*required_columns.map(&:to_sym))
      
      maintenance = Maintenance.new(maintenance_data)
      
      if maintenance.save
        puts "  ✅ Created maintenance for #{vehicle.registration_number}"
      else
        puts "  ❌ Failed: #{maintenance.errors.full_messages.join(', ')}"
      end
    end
  else
    puts "Maintenance records: #{Maintenance.count}"
    
    # Check user assignments
    if Maintenance.column_names.include?('user_id')
      puts "Maintenance by user:"
      User.all.each do |u|
        count = Maintenance.where(user_id: u.id).count
        puts "  #{u.email}: #{count}" if count > 0
      end
    end
  end
end

# 5. Fix trips user assignments
puts "\n=== TRIPS ==="
if defined?(Trip) && Trip.column_names.include?('user_id')
  trips_without_user = Trip.where(user_id: nil)
  trips_with_invalid_user = Trip.where.not(user_id: User.pluck(:id))
  
  if trips_without_user.any? || trips_with_invalid_user.any?
    puts "Fixing trip assignments..."
    
    total_fixed = 0
    (trips_without_user + trips_with_invalid_user).uniq.each do |trip|
      trip.update(user_id: user.id)
      total_fixed += 1
    end
    
    puts "✅ Fixed #{total_fixed} trip assignments"
  end
  
  puts "Trips by user:"
  User.all.each do |u|
    count = Trip.where(user_id: u.id).count
    puts "  #{u.email}: #{count}" if count > 0
  end
end

# 6. Final summary
puts "\n=== FINAL SUMMARY ==="
puts "User: #{user.email}"
puts "Vehicles: #{Vehicle.count}"
puts "Drivers: #{Driver.count}"
puts "Trips: #{Trip.count}"
puts "Maintenance: #{Maintenance.count}"

puts "\n=== RECOMMENDATIONS ==="
puts "1. Vehicle pictures are stored in the 'picture' column as strings"
puts "2. To add pictures, you need to set the 'picture' field to a file path or URL"
puts "3. Vehicles are linked to users through drivers"
puts "4. Usage analysis should work with trips data"
puts "5. Maintenance module should work with the sample data created"

puts "\n=== QUICK FIX FOR PICTURES ==="
puts "To add a picture to a vehicle, run in rails console:"
puts "  vehicle = Vehicle.find(1)"
puts "  vehicle.update(picture: '/path/to/image.jpg')"
puts "Or set it to a URL:"
puts "  vehicle.update(picture: 'https://example.com/bus.jpg')"
