# Create this file: db/migrate/20240108_assign_agencies_to_vehicles.rb
# rails generate migration AssignAgenciesToVehicles

class AssignAgenciesToVehicles < ActiveRecord::Migration[8.1]
  def up
    # First, ensure all agencies exist (using your seed data)
    Agency.find_or_create_by(code: 'VMCOTT') do |a|
      a.name = 'Vehicle Management Company of Trinidad and Tobago'
      a.theme = 'theme-1'
      a.description = 'Central vehicle fleet management agency for government vehicles'
    end
    
    Agency.find_or_create_by(code: 'TTPS') do |a|
      a.name = 'Trinidad and Tobago Police Service'
      a.theme = 'theme-6'
      a.description = 'Police Service vehicle fleet management'
    end
    
    Agency.find_or_create_by(code: 'TTDF') do |a|
      a.name = 'Trinidad and Tobago Defence Force'
      a.theme = 'theme-2'
      a.description = 'Military and defence force vehicle management'
    end
    
    Agency.find_or_create_by(code: 'PTSC') do |a|
      a.name = 'Public Transport Service Corporation'
      a.theme = 'theme-4'
      a.description = 'Public bus service and transportation fleet management'
    end
    
    # Now assign agencies based on service_owner
    Vehicle.all.each do |vehicle|
      agency = case vehicle.service_owner&.downcase
              when 'ptsc'
                Agency.find_by(code: 'PTSC')
              when 'police'
                Agency.find_by(code: 'TTPS')
              when 'fire service'
                Agency.find_by(code: 'TTDF')
              else
                # Default to VMCOTT for unknown or other service owners
                Agency.find_by(code: 'VMCOTT')
              end
      
      if agency
        vehicle.update_column(:agency_id, agency.id)
        puts "Assigned #{vehicle.license_plate} (#{vehicle.service_owner}) to #{agency.code}"
      end
    end
  end

  def down
    # Remove agency assignments
    Vehicle.update_all(agency_id: nil)
  end
end