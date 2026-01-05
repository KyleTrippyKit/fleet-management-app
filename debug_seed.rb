require_relative 'config/environment'

puts "=== DEBUG SEED ==="

# Check agencies
puts "Agencies in database: #{Agency.count}"
Agency.all.each do |a|
  puts "  #{a.id}: #{a.code} - #{a.name}"
end

# Find VMCOTT
vmcott = Agency.find_by(code: "VMCOTT")
if vmcott
  puts "✓ Found VMCOTT with ID: #{vmcott.id}"
else
  puts "✗ VMCOTT not found!"
  exit
end

# Try to create a user
puts "\nTrying to create user..."
user = User.new(
  email: "debug@test.com",
  password: "Debug123!",
  password_confirmation: "Debug123!",
  agency_id: vmcott.id,
  name: "Debug User",
  employee_id: "DEBUG-001",
  is_active: true
)

puts "User attributes before save:"
puts "  agency_id: #{user.agency_id}"
puts "  valid? #{user.valid?}"
puts "  errors: #{user.errors.full_messages}"

if user.save(validate: false)
  puts "✓ SUCCESS: User created with ID #{user.id}"
else
  puts "✗ FAILED: #{user.errors.full_messages}"
end
