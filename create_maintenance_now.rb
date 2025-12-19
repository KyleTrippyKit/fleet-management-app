puts "=== CREATING MAINTENANCE RECORDS NOW ==="

# First, let's check what we have
puts "Checking setup..."

# Check if models exist
if !defined?(Vehicle)
  puts "❌ Vehicle model not defined!"
  exit
end

if !defined?(Maintenance)
  puts "❌ Maintenance model not defined!"
  exit
end

# Check vehicles
vehicles = Vehicle.all
if vehicles.empty?
  puts "❌ No vehicles found!"
  exit
end

puts "Found #{vehicles.count} vehicles"
vehicles.each do |v|
  puts "  - #{v.registration_number || 'No reg'} (ID: #{v.id})"
end

# Create maintenance records
puts "\nCreating maintenance records..."

# Sample maintenance data
maintenance_templates = [
  {
    description: "Oil change and filter replacement",
    cost: 89.99,
    category: "Preventive",
    service_type: "Routine",
    details: "Changed engine oil and replaced oil filter with OEM parts.",
    notes: "Used synthetic 5W-30 oil. Reset maintenance indicator."
  },
  {
    description: "Tire rotation and alignment",
    cost: 120.50,
    category: "Preventive", 
    service_type: "Routine",
    details: "Rotated all four tires and performed wheel alignment check.",
    notes: "Tire pressure adjusted to manufacturer specifications."
  },
  {
    description: "Brake system inspection",
    cost: 75.00,
    category: "Safety",
    service_type: "Inspection",
    details: "Comprehensive brake system inspection including pads, rotors, and fluid.",
    notes: "Brake fluid level good, pads at 70% remaining."
  },
  {
    description: "Engine air filter replacement",
    cost: 45.00,
    category: "Preventive",
    service_type: "Routine", 
    details: "Replaced engine air filter to improve airflow and fuel efficiency.",
    notes: "Old filter was moderately dirty."
  },
  {
    description: "Transmission service",
    cost: 225.00,
    category: "Preventive",
    service_type: "Scheduled",
    details: "Drain and fill transmission fluid, replaced filter.",
    notes: "Used manufacturer-recommended transmission fluid."
  }
]

created = 0
vehicles.each do |vehicle|
  puts "\nCreating maintenance for #{vehicle.registration_number || 'Vehicle'} (ID: #{vehicle.id}):"
  
  # Create 3-4 maintenance records per vehicle
  records_to_create = rand(3..4)
  
  records_to_create.times do |i|
    template = maintenance_templates.sample.dup
    
    # Calculate dates
    days_ago = rand(1..365)
    maintenance_date = Date.today - days_ago
    
    # Build maintenance data
    maintenance_data = {
      vehicle_id: vehicle.id,
      date: maintenance_date,
      start_date: maintenance_date - rand(0..1).days,
      end_date: maintenance_date + rand(0..2).days,
      description: template[:description],
      cost: template[:cost],
      category: template[:category],
      service_type: template[:service_type],
      details: template[:details],
      notes: template[:notes],
      status: ["completed", "scheduled", "in_progress"].sample,
      mileage: vehicle.mileage ? [vehicle.mileage - rand(100..5000), 0].max : rand(5000..50000)
    }
    
    # Add optional fields if they exist in the model
    if Maintenance.column_names.include?('urgency')
      maintenance_data[:urgency] = ["low", "medium", "high"].sample
    end
    
    if Maintenance.column_names.include?('technician')
      maintenance_data[:technician] = ["Alex Johnson", "Maria Garcia", "James Wilson", "Sarah Chen"].sample
    end
    
    if Maintenance.column_names.include?('part_in_stock')
      maintenance_data[:part_in_stock] = [true, false].sample
    end
    
    if Maintenance.column_names.include?('next_due_date')
      maintenance_data[:next_due_date] = maintenance_date + rand(90..180).days
    end
    
    # Create the record
    begin
      maintenance = Maintenance.new(maintenance_data)
      
      if maintenance.save
        created += 1
        puts "  ✅ #{maintenance_data[:description]} (#{maintenance_data[:status]})"
      else
        puts "  ❌ Failed: #{maintenance.errors.full_messages.join(', ')}"
        # Try without optional fields
        simplified_data = maintenance_data.slice(:vehicle_id, :date, :description, :status)
        maintenance2 = Maintenance.new(simplified_data)
        if maintenance2.save
          created += 1
          puts "  ✅ Created simplified record"
        end
      end
    rescue => e
      puts "  ❌ Error: #{e.message}"
    end
  end
end

puts "\n=== SUMMARY ==="
puts "Created #{created} maintenance records"
puts "Total maintenance records in database: #{Maintenance.count}"

if Maintenance.count > 0
  puts "\nSample of created records:"
  Maintenance.order(created_at: :desc).limit(3).each do |m|
    vehicle = Vehicle.find_by(id: m.vehicle_id)
    vehicle_name = vehicle ? vehicle.registration_number : "Vehicle #{m.vehicle_id}"
    puts "  #{m.date}: #{vehicle_name} - #{m.description} (#{m.status})"
  end
end

puts "\n=== VERIFICATION ==="
puts "To verify, run in rails console:"
puts "  Maintenance.count"
puts "  Maintenance.first"
puts "Or check your app at /maintenances"
