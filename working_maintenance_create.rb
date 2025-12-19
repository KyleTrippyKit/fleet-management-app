puts "=== CREATING WORKING MAINTENANCE RECORDS ==="

# First, check if we have service providers
if defined?(ServiceProvider)
  service_providers = ServiceProvider.all
  if service_providers.empty?
    puts "No service providers found. Creating one..."
    sp = ServiceProvider.create!(name: "Default Service Center", contact: "555-0123")
    service_providers = [sp]
  end
  puts "Available service providers: #{service_providers.map(&:name).join(', ')}"
else
  puts "⚠️ ServiceProvider model not defined"
  # We'll need to create maintenance without service_provider_id
end

# Now create maintenance records
created = 0
Vehicle.all.each do |vehicle|
  puts "\nVehicle: #{vehicle.registration_number} (ID: #{vehicle.id})"
  
  # Create 2-3 maintenance records per vehicle
  rand(2..3).times do |i|
    # Choose random values from allowed lists
    status = ["Pending", "Completed"].sample
    assignment_type = ["stores", "purchasing"].sample
    
    # Only need service_provider if not completed
    service_provider_id = nil
    if status != "Completed" && defined?(ServiceProvider) && ServiceProvider.any?
      service_provider_id = ServiceProvider.first.id
    end
    
    # Dates
    days_ago = rand(1..90)
    date = Date.today - days_ago
    
    # Create maintenance data
    maintenance_data = {
      vehicle_id: vehicle.id,
      date: date,
      start_date: date - rand(0..2).days,
      end_date: date + rand(0..1).days,
      details: "Maintenance #{i+1} for #{vehicle.registration_number}",
      notes: "Standard maintenance performed",
      status: status,
      assignment_type: assignment_type,
      category: ["Preventive", "Corrective", "Emergency"].sample,
      service_type: ["Routine", "Scheduled", "Emergency"].sample,
      cost: rand(50..300),
      mileage: vehicle.mileage ? [vehicle.mileage - rand(100..5000), 0].max : rand(5000..50000)
    }
    
    # Add service_provider_id if we have one and status is not Completed
    if service_provider_id && status != "Completed"
      maintenance_data[:service_provider_id] = service_provider_id
    end
    
    # Add next_due_date for Pending records
    if status == "Pending"
      maintenance_data[:next_due_date] = date + rand(30..180).days
    end
    
    # Create the maintenance record
    maintenance = Maintenance.new(maintenance_data)
    
    if maintenance.save
      created += 1
      puts "  ✅ #{maintenance_data[:details]} (#{status})"
    else
      puts "  ❌ Failed: #{maintenance.errors.full_messages.join(', ')}"
      
      # Try alternative: set status to Completed to bypass service_provider requirement
      if maintenance.errors.include?("Service provider can't be blank")
        maintenance_data[:status] = "Completed"
        maintenance_data.delete(:service_provider_id)
        maintenance2 = Maintenance.new(maintenance_data)
        
        if maintenance2.save
          created += 1
          puts "  ✅ Created as Completed (no service provider needed)"
        else
          puts "  ❌ Still failed: #{maintenance2.errors.full_messages.join(', ')}"
        end
      end
    end
  end
end

puts "\n=== RESULTS ==="
puts "Created #{created} maintenance records"
puts "Total maintenance records: #{Maintenance.count}"

if Maintenance.count > 0
  puts "\nBreakdown:"
  puts "By status:"
  Maintenance.group(:status).count.each do |status, count|
    puts "  #{status}: #{count}"
  end
  
  puts "\nBy vehicle:"
  Maintenance.group(:vehicle_id).count.each do |vehicle_id, count|
    vehicle = Vehicle.find_by(id: vehicle_id)
    name = vehicle ? vehicle.registration_number : "Vehicle #{vehicle_id}"
    puts "  #{name}: #{count}"
  end
  
  puts "\nSample records:"
  Maintenance.limit(3).each do |m|
    puts "  ID #{m.id}: #{m.date} - #{m.details[0..40]}... (#{m.status})"
  end
end

puts "\n=== NEXT ==="
puts "Check your app at /maintenances"
puts "Or run: rails console"
puts "  Maintenance.count"
puts "  Maintenance.all.each { |m| puts \"\#{m.id}: \#{m.details}\" }"
