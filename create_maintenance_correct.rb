puts "=== CREATING MAINTENANCE RECORDS CORRECTLY ==="

# Check columns
puts "Maintenance columns: #{Maintenance.column_names.join(', ')}" if defined?(Maintenance)

# Sample maintenance data using correct column names
maintenance_templates = [
  {
    details: "Oil change and filter replacement",
    cost: 89.99,
    category: "Preventive",
    service_type: "Routine",
    notes: "Changed engine oil and replaced oil filter with OEM parts. Used synthetic 5W-30 oil."
  },
  {
    details: "Tire rotation and alignment",
    cost: 120.50,
    category: "Preventive", 
    service_type: "Routine",
    notes: "Rotated all four tires and performed wheel alignment check. Tire pressure adjusted."
  },
  {
    details: "Brake system inspection",
    cost: 75.00,
    category: "Safety",
    service_type: "Inspection",
    notes: "Comprehensive brake system inspection including pads, rotors, and fluid."
  },
  {
    details: "Engine air filter replacement",
    cost: 45.00,
    category: "Preventive",
    service_type: "Routine", 
    notes: "Replaced engine air filter to improve airflow and fuel efficiency."
  },
  {
    details: "Transmission service",
    cost: 225.00,
    category: "Preventive",
    service_type: "Scheduled",
    notes: "Drain and fill transmission fluid, replaced filter with OEM parts."
  }
]

created = 0
Vehicle.all.each do |vehicle|
  puts "\nCreating maintenance for #{vehicle.registration_number || 'Vehicle'} (ID: #{vehicle.id}):"
  
  # Create 2-3 maintenance records per vehicle
  rand(2..3).times do
    template = maintenance_templates.sample.dup
    
    # Calculate dates
    days_ago = rand(1..180)
    maintenance_date = Date.today - days_ago
    
    # Build maintenance data
    maintenance_data = {
      vehicle_id: vehicle.id,
      date: maintenance_date,
      start_date: maintenance_date - rand(0..1).days,
      end_date: maintenance_date + rand(0..2).days,
      details: template[:details],
      notes: template[:notes],
      cost: template[:cost],
      category: template[:category],
      service_type: template[:service_type],
      status: ["completed", "scheduled", "in_progress"].sample,
      mileage: vehicle.mileage ? [vehicle.mileage - rand(100..5000), 0].max : rand(5000..50000)
    }
    
    # Add optional fields
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
        puts "  ✅ #{maintenance_data[:details][0..50]}... (#{maintenance_data[:status]})"
      else
        puts "  ❌ Failed: #{maintenance.errors.full_messages.join(', ')}"
        
        # Try with minimal required fields
        minimal_data = {
          vehicle_id: vehicle.id,
          date: maintenance_date,
          details: template[:details],
          status: "completed"
        }
        
        maintenance2 = Maintenance.new(minimal_data)
        if maintenance2.save
          created += 1
          puts "  ✅ Created minimal record"
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
    puts "  #{m.date}: #{vehicle_name} - #{m.details[0..50]}... (#{m.status})"
  end
  
  puts "\nBreakdown by status:"
  Maintenance.group(:status).count.each do |status, count|
    puts "  #{status || 'nil'}: #{count}"
  end
end

puts "\n=== NEXT STEPS ==="
puts "1. Check your app at /maintenances"
puts "2. If not showing, check MaintenanceController#index"
puts "3. Verify views are using @maintenances variable"
