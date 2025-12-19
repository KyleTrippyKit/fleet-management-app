puts "=== CHECKING VEHICLE_USAGES DATA ==="

if defined?(VehicleUsage)
  puts "VehicleUsage model exists"
  puts "Total records: #{VehicleUsage.count}"
  
  # Check first record
  if VehicleUsage.any?
    usage = VehicleUsage.first
    puts "\nFirst VehicleUsage record:"
    puts "  Class: #{usage.class}"
    puts "  ID: #{usage.id}"
    puts "  Has vehicle method? #{usage.respond_to?(:vehicle)}"
    puts "  Vehicle ID: #{usage.vehicle_id}"
    
    if usage.respond_to?(:vehicle)
      puts "  Vehicle: #{usage.vehicle.registration_number if usage.vehicle}"
    end
  end
  
  # Check if @vehicle_usages might be hashes
  puts "\nChecking raw SQL result:"
  result = ActiveRecord::Base.connection.execute("SELECT * FROM vehicle_usages LIMIT 1")
  if result.any?
    row = result.first
    puts "  Raw SQL returns: #{row.class}"
    puts "  Is it a hash? #{row.is_a?(Hash)}"
    puts "  Keys: #{row.keys if row.respond_to?(:keys)}"
  end
end

# Check controller
controller_file = 'app/controllers/vehicle_usages_controller.rb'
if File.exist?(controller_file)
  puts "\n=== CONTROLLER CODE ==="
  content = File.read(controller_file)
  if content.include?('def index')
    puts "Index action found"
    # Show the index method
    index_start = content.index('def index')
    index_end = content.index('def ', index_start + 1) || content.length
    puts content[index_start...index_end]
  end
end
