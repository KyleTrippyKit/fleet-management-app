puts "=== CLEANING DATABASE ==="
User.delete_all
Agency.delete_all

puts "=== CREATING AGENCIES ==="
agencies_data = [
  { name: "Vehicle Management Company of Trinidad and Tobago", code: "VMCOTT", theme: "theme-1" },
  { name: "Trinidad and Tobago Police Service", code: "TTPS", theme: "theme-6" },
  { name: "Trinidad and Tobago Defence Force", code: "TTDF", theme: "theme-2" },
  { name: "Public Transport Service Corporation", code: "PTSC", theme: "theme-4" }
]

agencies = {}
agencies_data.each do |data|
  agency = Agency.create!(data)
  agencies[data[:code]] = agency
  puts "✓ Created agency: #{data[:code]}"
end

puts "\n=== CREATING USERS ==="
users_data = [
  # PTSC Users
  { email: "fleet.manager@ptsc.gov.tt", password: "password123", name: "PTSC Fleet Manager", role: "fleet_manager", agency_code: "PTSC" },
  { email: "maintenance.supervisor@ptsc.gov.tt", password: "password123", name: "Maintenance Supervisor", role: "maintenance_supervisor", agency_code: "PTSC" },
  { email: "finance@ptsc.gov.tt", password: "password123", name: "Finance Officer", role: "finance", agency_code: "PTSC" },
  { email: "driver.john@ptsc.gov.tt", password: "password123", name: "John Driver", role: "driver", agency_code: "PTSC" },
  { email: "admin@ptsc.gov.tt", password: "password123", name: "PTSC Administrator", role: "admin", agency_code: "PTSC" },
  
  # Other agency admins
  { email: "admin@vmcott.gov.tt", password: "password123", name: "VMCOTT Administrator", role: "admin", agency_code: "VMCOTT" },
  { email: "admin@ttps.gov.tt", password: "password123", name: "TTPS Administrator", role: "admin", agency_code: "TTPS" },
  { email: "admin@ttdf.gov.tt", password: "password123", name: "TTDF Administrator", role: "admin", agency_code: "TTDF" },
  
  # Test users
  { email: "test@vmcott.gov.tt", password: "test123", name: "VMCOTT Test User", role: "fleet_manager", agency_code: "VMCOTT" },
  { email: "test@ttps.gov.tt", password: "test123", name: "TTPS Test User", role: "fleet_manager", agency_code: "TTPS" },
  { email: "test@ttdf.gov.tt", password: "test123", name: "TTDF Test User", role: "fleet_manager", agency_code: "TTDF" },
  { email: "test@ptsc.gov.tt", password: "test123", name: "PTSC Test User", role: "fleet_manager", agency_code: "PTSC" }
]

users_data.each do |data|
  agency = agencies[data[:agency_code]]
  user = User.create!(
    email: data[:email],
    password: data[:password],
    password_confirmation: data[:password],
    name: data[:name],
    role: data[:role],
    agency: agency
  )
  puts "✓ Created user: #{data[:email]} (#{data[:role]}) for #{data[:agency_code]}"
end

puts "\n=== VERIFICATION ==="
puts "Total Agencies: #{Agency.count}"
puts "Total Users: #{User.count}"

puts "\n🎉 DATABASE SEEDED SUCCESSFULLY!"
puts "\n=== LOGIN CREDENTIALS ==="
puts "PTSC Fleet Manager:       fleet.manager@ptsc.gov.tt / password123"
puts "PTSC Maintenance:         maintenance.supervisor@ptsc.gov.tt / password123"
puts "PTSC Finance:             finance@ptsc.gov.tt / password123"
puts "PTSC Driver:              driver.john@ptsc.gov.tt / password123"
puts "PTSC Admin:               admin@ptsc.gov.tt / password123"
puts "VMCOTT Admin:             admin@vmcott.gov.tt / password123"
puts "TTPS Admin:               admin@ttps.gov.tt / password123"
puts "TTDF Admin:               admin@ttdf.gov.tt / password123"
