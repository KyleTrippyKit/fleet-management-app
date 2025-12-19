puts "=== RESTORING MAINTENANCE RECORDS ==="

# First, check current state
puts "Checking current maintenance records..."
if defined?(Maintenance)
  puts "Maintenance model exists"
  puts "Total maintenance records: #{Maintenance.count}"
  
  if Maintenance.count == 0
    puts "\n❌ No maintenance records found!"
    puts "Let me check what happened..."
    
    # Check if the table exists
    if ActiveRecord::Base.connection.table_exists?('maintenances')
      puts "Maintenances table exists"
      
      # Check schema
      columns = ActiveRecord::Base.connection.columns('maintenances').map(&:name)
      puts "Maintenance columns: #{columns.join(', ')}"
      
      # Check for any deleted records in the database
      result = ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM maintenances")
      db_count = result.first[0]
      puts "Records in database table: #{db_count}"
      
      if db_count > 0
        puts "\n⚠️  Records exist in database but Rails can't see them!"
        puts "Possible issues:"
        puts "1. Database connection problem"
        puts "2. Model scope/validation issue"
        puts "3. Data belongs to different user"
        
        # Show sample data
        puts "\nSample data from database:"
        samples = ActiveRecord::Base.connection.execute("SELECT * FROM maintenances LIMIT 3")
        samples.each do |row|
          puts "  ID: #{row['id'] || row[0]}, Vehicle: #{row['vehicle_id'] || row[1]}, Description: #{row['description'] || row[2]}"
        end
      end
    else
      puts "❌ Maintenances table doesn't exist!"
    end
  else
    puts "\n✅ Maintenance records exist:"
    Maintenance.all.each do |m|
      puts "  ID: #{m.id}, Vehicle: #{m.vehicle_id}, Date: #{m.date}, Desc: #{m.description}"
    end
  end
end

# Check if maintenance was deleted with users
puts "\n=== CHECKING FOR DELETED DATA ==="
if defined?(Vehicle) && Vehicle.count > 0
  puts "Vehicles exist: #{Vehicle.count}"
  
  # Check each vehicle for maintenance
  puts "\nChecking vehicles for maintenance records:"
  Vehicle.all.each do |vehicle|
    if vehicle.respond_to?(:maintenances)
      count = vehicle.maintenances.count
      if count > 0
        puts "✅ Vehicle #{vehicle.registration_number}: #{count} maintenance records"
      else
        puts "❌ Vehicle #{vehicle.registration_number}: No maintenance records"
      end
    end
  end
end

# Create sample maintenance if needed
puts "\n=== CREATING SAMPLE MAINTENANCE ==="
print "Create sample maintenance records? (y/n): "
answer = gets.chomp.downcase

if answer == 'y' && defined?(Maintenance) && defined?(Vehicle)
  puts "Creating sample maintenance records..."
  
  # Get current user for user_id if needed
  user = User.find_by(email: 'kylerigsby10@yahoo.com')
  
  # Sample maintenance data
  maintenance_types = [
    { description: "Oil change and filter replacement", cost: 89.99, duration: 1 },
    { description: "Tire rotation and alignment check", cost: 120.50, duration: 2 },
    { description: "Brake inspection and pad replacement", cost: 250.00, duration: 3 },
    { description: "Engine tune-up and spark plugs", cost: 180.00, duration: 2 },
    { description: "Transmission fluid change", cost: 150.00, duration: 2 },
    { description: "Coolant system flush", cost: 95.00, duration: 1 },
    { description: "Air conditioning service", cost: 200.00, duration: 2 },
    { description: "Wheel bearing replacement", cost: 300.00, duration: 4 },
    { description: "Suspension check and adjustment", cost: 175.00, duration: 3 },
    { description: "Exhaust system inspection", cost: 85.00, duration: 1 }
  ]
  
  created = 0
  Vehicle.all.each do |vehicle|
    # Create 2-3 maintenance records per vehicle
    rand(2..3).times do |i|
      maintenance_data = maintenance_types.sample.dup
      
      # Set basic fields
      maintenance_data[:vehicle_id] = vehicle.id
      maintenance_data[:date] = Date.today - rand(1..90).days
      maintenance_data[:mileage] = vehicle.mileage ? vehicle.mileage - rand(100..5000) : rand(5000..50000)
      maintenance_data[:status] = ["completed", "scheduled", "in_progress"].sample
      
      # Check required columns and add user_id if needed
      if Maintenance.column_names.include?('user_id') && user
        maintenance_data[:user_id] = user.id
      end
      
      # Check for other required columns
      if Maintenance.column_names.include?('details') && !maintenance_data[:details]
        maintenance_data[:details] = "Standard maintenance service"
      end
      
      if Maintenance.column_names.include?('notes') && !maintenance_data[:notes]
        maintenance_data[:notes] = "Performed as per maintenance schedule"
      end
      
      # Remove any keys that aren't columns
      allowed_keys = Maintenance.column_names.map(&:to_sym) - [:id, :created_at, :updated_at]
      maintenance_data = maintenance_data.slice(*allowed_keys)
      
      # Create the maintenance record
      maintenance = Maintenance.new(maintenance_data)
      
      if maintenance.save
        created += 1
        puts "  ✅ Created for #{vehicle.registration_number}: #{maintenance_data[:description]}"
      else
        puts "  ❌ Failed: #{maintenance.errors.full_messages.join(', ')}"
      end
    end
  end
  
  puts "\n✅ Created #{created} maintenance records"
end

# Final check
puts "\n=== FINAL MAINTENANCE STATUS ==="
if defined?(Maintenance)
  total = Maintenance.count
  puts "Total maintenance records: #{total}"
  
  if total > 0
    puts "\nRecent maintenance:"
    Maintenance.order(date: :desc).limit(5).each do |m|
      vehicle = Vehicle.find_by(id: m.vehicle_id)
      vehicle_name = vehicle ? vehicle.registration_number : "Vehicle #{m.vehicle_id}"
      puts "  #{m.date}: #{vehicle_name} - #{m.description} (#{m.status})"
    end
  end
end

puts "\n=== TROUBLESHOOTING ==="
puts "If maintenance records still don't show up:"
puts "1. Check app/views/maintenances/index.html.erb - make sure it's displaying records"
puts "2. Check Maintenance model for scopes or default_scope that might hide records"
puts "3. Check if records belong to a different user (check user_id)"
puts "4. Run 'rails console' and check Maintenance.all"
