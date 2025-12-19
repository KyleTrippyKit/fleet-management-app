puts "=== CHECKING REAL DATA STRUCTURE ==="

# Current user
user = User.find_by(email: 'kylerigsby10@yahoo.com')
puts "User: #{user.email} (ID: #{user.id})"

# Check all models
puts "\n=== ALL MODELS AND THEIR DATA ==="
models = {
  'Vehicle' => :vehicles,
  'Maintenance' => :maintenances,
  'Trip' => :trips,
  'Driver' => :drivers,
  'DamageReport' => :damage_reports,
  'VehicleUsage' => :vehicle_usages,
  'Part' => :parts,
  'MaintenanceTask' => :maintenance_tasks
}

models.each do |model_name, table_name|
  begin
    model_class = model_name.constantize
    puts "\n#{model_name}: #{model_class.count} records"
    
    if model_class.count > 0
      # Show first few
      model_class.limit(3).each do |record|
        if record.respond_to?(:name)
          puts "  - #{record.name} (ID: #{record.id})"
        elsif record.respond_to?(:registration_number)
          puts "  - #{record.registration_number} (ID: #{record.id})"
        elsif record.respond_to?(:description) && record.description.present?
          puts "  - #{record.description[0..50]}... (ID: #{record.id})"
        else
          puts "  - ID: #{record.id}"
        end
        
        # Check user association
        if record.respond_to?(:user) && record.user
          puts "    Belongs to user: #{record.user.email}"
        elsif record.respond_to?(:user_id) && record.user_id
          owner = User.find_by(id: record.user_id)
          puts "    User ID: #{record.user_id} (#{owner ? owner.email : 'user not found'})"
        end
      end
    end
  rescue => e
    puts "#{model_name}: Error - #{e.message}"
  end
end

# Check Active Storage attachments
puts "\n=== ACTIVE STORAGE ATTACHMENTS ==="
if ActiveRecord::Base.connection.table_exists?('active_storage_attachments')
  count = ActiveRecord::Base.connection.execute(
    "SELECT COUNT(*) FROM active_storage_attachments"
  ).first[0]
  puts "Total attachments: #{count}"
  
  if count > 0
    # Group by record type
    attachments_by_type = ActiveRecord::Base.connection.execute(
      "SELECT record_type, COUNT(*) as count FROM active_storage_attachments GROUP BY record_type"
    ).to_a
    
    attachments_by_type.each do |row|
      puts "  #{row['record_type']}: #{row['count']} attachments"
      
      # Show details for Vehicle attachments
      if row['record_type'] == 'Vehicle'
        vehicle_attachments = ActiveRecord::Base.connection.execute(
          "SELECT record_id, name FROM active_storage_attachments WHERE record_type = 'Vehicle'"
        ).to_a
        
        vehicle_attachments.each do |attachment|
          vehicle = Vehicle.find_by(id: attachment['record_id'])
          puts "    Vehicle ID #{attachment['record_id']}: #{attachment['name']} (#{vehicle ? vehicle.registration_number : 'vehicle not found'})"
        end
      end
    end
  end
end

# Check user's associations
puts "\n=== USER'S ASSOCIATIONS ==="
if user
  puts "User #{user.email} owns:"
  
  # Check each association
  if user.respond_to?(:vehicles)
    puts "  Vehicles: #{user.vehicles.count}"
    user.vehicles.each do |vehicle|
      puts "    - #{vehicle.registration_number || 'Unnamed'} (ID: #{vehicle.id})"
    end
  end
  
  if user.respond_to?(:maintenances)
    puts "  Maintenances: #{user.maintenances.count}"
  end
  
  if user.respond_to?(:trips)
    puts "  Trips: #{user.trips.count}"
  end
  
  if user.respond_to?(:drivers)
    puts "  Drivers: #{user.drivers.count}"
  end
end

# Check for orphaned records
puts "\n=== CHECKING FOR ORPHANED RECORDS ==="
models.each do |model_name, table_name|
  begin
    model_class = model_name.constantize
    if model_class.column_names.include?('user_id')
      orphaned = model_class.where.not(user_id: nil).where(
        "user_id NOT IN (SELECT id FROM users)"
      ).count
      
      if orphaned > 0
        puts "⚠️  #{model_name}: #{orphaned} records reference non-existent users"
      end
    end
  rescue => e
    # Skip errors
  end
end
