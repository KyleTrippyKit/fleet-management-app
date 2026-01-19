# db/seeds/mock_data.rb
require_relative '../app/services/mock_inventory_generator'

namespace :mock do
  desc 'Generate mock data for demo system'
  task generate: :environment do
    puts "Generating mock data for demo system..."
    
    # Create agencies if they don't exist
    agencies = {
      'PTSC' => 'Public Transport Service Corporation',
      'TTPS' => 'Trinidad and Tobago Police Service',
      'TTDF' => 'Trinidad and Tobago Defence Force',
      'VMCOTT' => 'Vehicle Maintenance Company of Trinidad and Tobago'
    }
    
    agencies.each do |code, name|
      Agency.find_or_create_by!(code: code) do |agency|
        agency.name = name
        agency.theme = 'theme-1'
      end
    end
    
    # Create demo users
    admin_user = User.find_or_create_by!(email: 'admin@demo.tt') do |user|
      user.name = 'Demo Administrator'
      user.password = 'password123'
      user.agency = Agency.find_by(code: 'VMCOTT')
      user.role = 'admin'
    end
    
    ptsc_user = User.find_or_create_by!(email: 'manager@ptsc.tt') do |user|
      user.name = 'PTSC Manager'
      user.password = 'password123'
      user.agency = Agency.find_by(code: 'PTSC')
      user.role = 'fleet_manager'
    end
    
    puts "✅ Created demo users"
    puts "Demo credentials:"
    puts "  Admin: admin@demo.tt / password123"
    puts "  PTSC Manager: manager@ptsc.tt / password123"
  end
end

# Run with: rails mock:generate