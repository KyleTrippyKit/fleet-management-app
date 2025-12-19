puts "=== VERIFYING APP STATUS ==="

# 1. Check Users
puts "\n=== USERS ==="
puts "Total users: #{User.count}"
User.all.each do |user|
  puts "  - #{user.email} (ID: #{user.id})"
end

# 2. Check Vehicles
puts "\n=== VEHICLES ==="
puts "Total vehicles: #{Vehicle.count}"
Vehicle.all.each do |vehicle|
  puts "  - #{vehicle.registration_number} (ID: #{vehicle.id})"
  puts "    Picture: #{vehicle.picture.present? ? '✅ Set' : '❌ Missing'}"
  
  # Check maintenance count
  if vehicle.respond_to?(:maintenances)
    puts "    Maintenance: #{vehicle.maintenances.count} records"
  end
end

# 3. Check Maintenance
puts "\n=== MAINTENANCE ==="
puts "Total maintenance records: #{Maintenance.count}"
puts "By status:"
Maintenance.group(:status).count.each do |status, count|
  puts "  #{status}: #{count}"
end

# 4. Check Active Storage
puts "\n=== ACTIVE STORAGE ==="
if ActiveRecord::Base.connection.table_exists?('active_storage_attachments')
  count = ActiveRecord::Base.connection.execute(
    "SELECT COUNT(*) FROM active_storage_attachments"
  ).first[0]
  puts "Attachments: #{count}"
else
  puts "Active Storage not configured"
end

# 5. Check for pictures in vehicle.picture column
puts "\n=== VEHICLE PICTURES (string column) ==="
vehicles_with_pictures = Vehicle.where.not(picture: [nil, ''])
vehicles_without_pictures = Vehicle.where(picture: [nil, ''])
puts "Vehicles with pictures: #{vehicles_with_pictures.count}/#{Vehicle.count}"

if vehicles_without_pictures.any?
  puts "\nVehicles needing pictures:"
  vehicles_without_pictures.each do |vehicle|
    puts "  - #{vehicle.registration_number} (ID: #{vehicle.id})"
  end
end

# 6. Recommendations
puts "\n=== RECOMMENDATIONS ==="
puts "✅ Maintenance records created: #{Maintenance.count}"
puts "✅ Vehicles: #{Vehicle.count}"
puts "✅ Users: #{User.count}"

if vehicles_without_pictures.count > 0
  puts "\n⚠️  Some vehicles don't have pictures in the 'picture' column."
  puts "   To add pictures, run:"
  puts "   rails runner 'Vehicle.where(picture: nil).each_with_index { |v,i| v.update(picture: \"https://images.unsplash.com/photo-15#{(i % 5) + 1}...jpg\") }'"
end

puts "\n=== TESTING APP PAGES ==="
puts "1. Visit http://localhost:3000/maintenances - Should show maintenance records"
puts "2. Visit http://localhost:3000/vehicles - Should show vehicles (some with pictures)"
puts "3. Visit http://localhost:3000/ - Home page"

puts "\n=== IF MAINTENANCE NOT SHOWING ==="
puts "Check these common issues:"
puts "1. Maintenance controller might filter by current_user"
puts "2. Views might have display logic issues"
puts "3. Routes might be different"

# Quick check of maintenance controller
puts "\n=== QUICK CONTROLLER CHECK ==="
controller_file = 'app/controllers/maintenances_controller.rb'
if File.exist?(controller_file)
  content = File.read(controller_file)
  if content.include?('def index')
    puts "MaintenancesController has index action"
    # Check if it filters by current_user
    if content.include?('current_user.maintenances')
      puts "⚠️  Controller filters by current_user - make sure you're logged in as kylerigsby10@yahoo.com"
    end
  end
else
  puts "MaintenancesController not found"
end
