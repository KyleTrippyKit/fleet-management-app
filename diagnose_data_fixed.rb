puts "=== DIAGNOSING DATA ISSUES ==="

# 1. Check current user
current_user = User.find_by(email: 'kylerigsby10@yahoo.com')
if current_user
  puts "Current user: #{current_user.email} (ID: #{current_user.id})"
else
  puts "Current user not found!"
  exit
end

# 2. Check what tables exist and their data
puts "\n=== CHECKING DATA TABLES ==="

tables_to_check = %w[buses maintenance_records usage_logs pictures images photos attachments]
tables_to_check.each do |table_name|
  if ActiveRecord::Base.connection.table_exists?(table_name)
    count_result = ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM #{table_name}")
    count = count_result.first[0]
    puts "#{table_name}: #{count} records"
    
    # Check if it has user_id foreign key
    begin
      columns = ActiveRecord::Base.connection.columns(table_name)
      if columns.any? { |c| c.name == 'user_id' }
        # Check how many records belong to current user
        user_count_result = ActiveRecord::Base.connection.execute(
          "SELECT COUNT(*) FROM #{table_name} WHERE user_id = #{current_user.id}"
        )
        user_count = user_count_result.first[0]
        puts "  - Belongs to current user: #{user_count} records"
      end
    rescue => e
      puts "  - Error checking columns: #{e.message}"
    end
  else
    puts "#{table_name}: Table does not exist"
  end
end

# 3. Check for buses specifically
puts "\n=== CHECKING BUSES ==="
if ActiveRecord::Base.connection.table_exists?('buses')
  buses_result = ActiveRecord::Base.connection.execute("SELECT * FROM buses LIMIT 5")
  buses = buses_result.to_a
  puts "Buses found: #{buses.count}"
  buses.each do |bus|
    puts "  Bus ID: #{bus['id'] || bus[0]}, Name: #{bus['name'] || bus[1]}, User ID: #{bus['user_id'] || bus[2]}"
  end
else
  puts "Buses table does not exist"
end

# 4. Check for maintenance records
puts "\n=== CHECKING MAINTENANCE ==="
if ActiveRecord::Base.connection.table_exists?('maintenance_records')
  records_result = ActiveRecord::Base.connection.execute(
    "SELECT COUNT(*) as count, user_id FROM maintenance_records GROUP BY user_id"
  )
  records = records_result.to_a
  puts "Maintenance records by user:"
  if records.any?
    records.each do |record|
      puts "  User ID #{record['user_id'] || record[1]}: #{record['count'] || record[0]} records"
    end
  else
    puts "  No maintenance records found"
  end
else
  puts "Maintenance_records table does not exist"
end

# 5. Check for pictures/images
puts "\n=== CHECKING IMAGES ==="
# Common image/picture tables
image_tables = %w[active_storage_attachments active_storage_blobs pictures images]
image_tables.each do |table|
  if ActiveRecord::Base.connection.table_exists?(table)
    count_result = ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM #{table}")
    count = count_result.first[0]
    puts "#{table}: #{count} records"
    
    # Show some sample data for active storage
    if table == 'active_storage_attachments' && count > 0
      puts "  Sample attachments:"
      samples = ActiveRecord::Base.connection.execute(
        "SELECT record_type, record_id, name FROM active_storage_attachments LIMIT 3"
      ).to_a
      samples.each do |sample|
        puts "    - #{sample['record_type']} ##{sample['record_id']}: #{sample['name']}"
      end
    end
  else
    puts "#{table}: Table does not exist"
  end
end

# 6. Check all tables in database
puts "\n=== ALL TABLES IN DATABASE ==="
all_tables = ActiveRecord::Base.connection.tables
all_tables.each do |table|
  next if table == 'schema_migrations' || table == 'ar_internal_metadata'
  
  begin
    count_result = ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM #{table}")
    count = count_result.first[0]
    puts "#{table}: #{count} records"
  rescue => e
    puts "#{table}: Error - #{e.message}"
  end
end

# 7. Check your actual models
puts "\n=== CHECKING RAILS MODELS ==="
begin
  puts "User model exists: #{defined?(User)}"
  if defined?(Bus)
    puts "Bus model exists. Count: #{Bus.count rescue 'error'}"
    Bus.all.each do |bus|
      puts "  Bus: #{bus.name} (ID: #{bus.id}, User ID: #{bus.user_id})"
    end
  else
    puts "Bus model not defined"
  end
  
  if defined?(MaintenanceRecord)
    puts "MaintenanceRecord model exists. Count: #{MaintenanceRecord.count rescue 'error'}"
  else
    puts "MaintenanceRecord model not defined"
  end
rescue => e
  puts "Error checking models: #{e.message}"
end
