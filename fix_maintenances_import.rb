require 'csv'

puts "Fixing maintenance import..."

if File.exist?('maintenances_export.csv') && defined?(Maintenance)
  csv = CSV.read('maintenances_export.csv', headers: true)
  
  csv.each do |row|
    attrs = row.to_hash.except('id')
    
    # Find vehicle
    if attrs['vehicle_id']
      vehicle = Vehicle.find_by(id: attrs['vehicle_id']) || Vehicle.first
      attrs['vehicle_id'] = vehicle.id if vehicle
    end
    
    # Find service provider or create default
    if attrs['service_provider_id'].blank?
      # Create a default service provider if needed
      provider = ServiceProvider.first_or_create!(name: 'Default Provider')
      attrs['service_provider_id'] = provider.id
    end
    
    # Create maintenance
    Maintenance.create!(attrs)
    puts "Imported maintenance: #{attrs['date']}"
  end
end

puts "Maintenances imported: #{Maintenance.count}"
