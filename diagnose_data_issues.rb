puts "=== DIAGNOSING DATA ISSUES ==="

# 1. Check current user
current_user = User.find_by(email: 'kylerigsby10@yahoo.com')
puts "Current user: #{current_user.email} (ID: #{current_user.id})"

# 2. Check what tables exist and their data
puts "\n=== CHECKING DATA TABLES ==="

tables_to_check = %w[buses maintenance_records usage_logs pictures images photos attachments]
tables_to_check.each do |table_name|
  if ActiveRecord::Base.connection.table_exists?(table_name)
    count = ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM #{table_name}").first[0]
    puts "#{table_name}: #{count} records"
    
    # Check if it has user_id foreign key
    columns = ActiveRecord::Base.connection.columns(table_name)
    if columns.any? { |c| c.name == 'user_id' }
      # Check how many records belong to current user
      user_count = ActiveRecord::Base.connection.execute(
        "SELECT COUNT(*) FROM #{table_name} WHERE user_id = #{current_user.id}"
      ).first[0]
      puts "  - Belongs to current user: #{user_count} records"
      
      # Check total records with any user_id
      total_with_user = ActiveRecord::Base.connection.execute(
        "SELECT COUNT(*) FROM #{table_name} WHERE user_id IS NOT NULL"
      ).first[0]
      puts "  - Total with user_id: #{total_with_user} records"
    end
    
    # Check for sample data
    if count > 0 && count < 10
      puts "  - Sample IDs: #{ActiveRecord::Base.connection.execute("SELECT id FROM #{table_name} LIMIT 5").to_a.join(', ')}"
    end
  end
end

# 3. Check for buses specifically
puts "\n=== CHECKING BUSES ==="
if ActiveRecord::Base.connection.table_exists?('buses')
  buses = ActiveRecord::Base.connection.execute("SELECT * FROM buses LIMIT 5").to_a
  puts "Buses found: #{buses.count}"
  buses.each do |bus|
    puts "  Bus ID: #{bus['id'] || bus[0]}, Name: #{bus['name'] || bus[1]}, User ID: #{bus['user_id'] || bus[2]}"
  end
end

# 4. Check for maintenance records
puts "\n=== CHECKING MAINTENANCE ==="
if ActiveRecord::Base.connection.table_exists?('maintenance_records')
  records = ActiveRecord::Base.connection.execute(
    "SELECT COUNT(*) as count, user_id FROM maintenance_records GROUP BY user_id"
  ).to_a
  puts "Maintenance records by user:"
  records.each do |record|
    puts "  User ID #{record['user_id'] || record[1]}: #{record['count'] || record[0]} records"
  end
end

# 5. Check for pictures/images
puts "\n=== CHECKING IMAGES ==="
# Common image/picture tables
image_tables = %w[active_storage_attachments active_storage_blobs pictures images]
image_tables.each do |table|
  if ActiveRecord::Base.connection.table_exists?(table)
    count = ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM #{table}").first[0]
    puts "#{table}: #{count} records"
  end
end

# 6. Check if there are any foreign key violations
puts "\n=== CHECKING FOR ORPHANED RECORDS ==="
# Look for records that reference non-existent users
tables_to_check.each do |table|
  if ActiveRecord::Base.connection.table_exists?(table) &&
     ActiveRecord::Base.connection.columns(table).any? { |c| c.name == 'user_id' }
    
    orphaned = ActiveRecord::Base.connection.execute(
      "SELECT COUNT(*) FROM #{table} t WHERE t.user_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM users u WHERE u.id = t.user_id)"
    ).first[0]
    
    if orphaned > 0
      puts "⚠️  #{table}: #{orphaned} orphaned records (reference non-existent users)"
    end
  end
end
