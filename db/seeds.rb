puts "Seeding users..."
users = [
  { email: "admin@example.com", password: "password123", password_confirmation: "password123" },
  { email: "user1@example.com", password: "password123", password_confirmation: "password123" },
  { email: "user2@example.com", password: "password123", password_confirmation: "password123" }
].map { |u| User.create!(u) }

puts "Seeding vehicles..."
vehicles = [
  { make: "Toyota", model: "Corolla", vehicle_type: "Sedan", license_plate: "ABC123", registration_number: "REG123", chassis_number: "CH123", serial_number: "SN123", year_of_manufacture: 2020, service_owner: "PTSC" },
  { make: "Ford", model: "Focus", vehicle_type: "Hatchback", license_plate: "XYZ789", registration_number: "REG456", chassis_number: "CH456", serial_number: "SN456", year_of_manufacture: 2019, service_owner: "Police" }
].map { |v| Vehicle.create!(v) }

puts "Seeding drivers.."
drivers = [
  { name: "Frank", license_number: "Hbc 2054", phone: "2964764" },
  { name: "Sean", license_number: "Pdc 7547", phone: "7647454" },
  { name: "John", license_number: "Paz 9045", phone: "7021921" }
].map { |d| Driver.create!(d) }

puts "Seeding trips..."
now = Time.current


trips_data = [
  { vehicle: vehicles[0], driver: drivers[1], start_time: now - 2.hour, end_time: now - 1.hour, distance_km: 100 },
  { vehicle: vehicles[0], driver: drivers[2], start_time: now - 2.hours, end_time: now - 1.hours, distance_km: 80 },
  { vehicle: vehicles[1], driver: drivers[2], start_time: now - 2.hour, end_time: now - 1.hours, distance_km: 50 }
]

trips_data.each do |trip_attrs|
  Trip.create!(trip_attrs)
end

puts "Seeding complete!"
puts "You can log in with these users:"
users.each { |u| puts "Email: #{u.email} | Password: password123" }
