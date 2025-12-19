puts "=== DEEP CHECK OF MAINTENANCE DATA ==="

# 1. Direct database check
puts "Checking database directly..."
begin
  # Check if table exists
  if ActiveRecord::Base.connection.table_exists?('maintenances')
    puts "✅ Maintenances table exists"
    
    # Get count directly from database
    count_result = ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM maintenances")
    db_count = count_result.first[0]
    puts "Records in database: #{db_count}"
    
    if db_count > 0
      puts "\nSample maintenance records from database:"
      samples = ActiveRecord::Base.connection.execute("SELECT * FROM maintenances LIMIT 5")
      samples.each_with_index do |row, i|
        puts "\nRecord #{i+1}:"
        row.each_with_index do |value, idx|
          column_name = samples.columns[idx] rescue "col#{idx}"
          puts "  #{column_name}: #{value}" if value.present?
        end
      end
    else
      puts "⚠️  Table exists but is empty"
    end
  else
    puts "❌ Maintenances table doesn't exist!"
  end
rescue => e
  puts "❌ Error checking database: #{e.message}"
end

# 2. Check Migration history
puts "\n=== CHECKING MIGRATION STATUS ==="
begin
  # Check schema version
  version_result = ActiveRecord::Base.connection.execute("SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1")
  puts "Latest migration: #{version_result.first[0] rescue 'unknown'}"
  
  # Check if maintenance migration ran
  maintenance_migrations = ActiveRecord::Base.connection.execute(
    "SELECT version FROM schema_migrations WHERE version LIKE '%maintenance%'"
  ).to_a
  
  if maintenance_migrations.any?
    puts "Maintenance migrations found:"
    maintenance_migrations.each { |m| puts "  #{m[0]}" }
  else
    puts "No maintenance-specific migrations found"
  end
rescue => e
  puts "Error checking migrations: #{e.message}"
end

# 3. Check Model configuration
puts "\n=== CHECKING MAINTENANCE MODEL ==="
if defined?(Maintenance)
  puts "Maintenance model loaded"
  puts "Table name: #{Maintenance.table_name}"
  puts "Columns: #{Maintenance.column_names.join(', ')}"
  
  # Check for default_scope or other scopes
  puts "Default scope: #{Maintenance.default_scopes.any? ? 'Yes' : 'No'}"
  
  # Try to query with SQL
  puts "\nTrying raw SQL query through model:"
  begin
    results = Maintenance.find_by_sql("SELECT * FROM maintenances LIMIT 3")
    puts "Found #{results.count} records via raw SQL"
    results.each do |r|
      puts "  ID: #{r.id}, Vehicle: #{r.vehicle_id}"
    end
  rescue => e
    puts "  Error: #{e.message}"
  end
else
  puts "❌ Maintenance model not defined!"
end

# 4. Recommendations
puts "\n=== RECOMMENDATIONS ==="
if defined?(Maintenance) && Maintenance.count == 0
  puts "1. Run 'rails db:migrate:status' to check migrations"
  puts "2. Check if you have a seeds.rb file with maintenance data"
  puts "3. Check for CSV backups in the project"
  puts "4. If table is empty, create sample data with the previous script"
end
