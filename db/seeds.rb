puts "Seeding users..."
users = [
  { email: "admin@example.com", password: "password123", password_confirmation: "password123" },
  { email: "user1@example.com", password: "password123", password_confirmation: "password123" },
  { email: "user2@example.com", password: "password123", password_confirmation: "password123" }
].map { |u| User.create!(u) }

puts "Seeding vehicles..."
vehicle_data = [
  { make: "Ford", model: "Focus", vehicle_type: "Hatchback", license_plate: "XYZ-789", registration_number: "REG456", chassis_number: "CH456", serial_number: "SN456", year_of_manufacture: 2019, service_owner: "Police", image_file: "Ford.webp" },
  { make: "Higer", model: "Bus", vehicle_type: "Bus", license_plate: "HIG-001", registration_number: "REG789", chassis_number: "CH789", serial_number: "SN789", year_of_manufacture: 2021, service_owner: "PTSC", image_file: "Higer.jpg" },
  { make: "Isuzu", model: "D-Max", vehicle_type: "Truck", license_plate: "ISU-123", registration_number: "REG123", chassis_number: "CH123", serial_number: "SN123", year_of_manufacture: 2020, service_owner: "PTSC", image_file: "Isuzu.jpg" },
  { make: "Nissan", model: "Sentra", vehicle_type: "Sedan", license_plate: "NIS-456", registration_number: "REG456", chassis_number: "CH456", serial_number: "SN456", year_of_manufacture: 2018, service_owner: "Police", image_file: "Nissan.webp" },
  { make: "Suzuki", model: "Swift", vehicle_type: "Hatchback", license_plate: "SUZ-789", registration_number: "REG789", chassis_number: "CH789", serial_number: "SN789", year_of_manufacture: 2022, service_owner: "PTSC", image_file: "Suzuki.jpg" },
  { make: "Toyota", model: "Corolla", vehicle_type: "Sedan", license_plate: "TOY-123", registration_number: "REG123", chassis_number: "CH123", serial_number: "SN123", year_of_manufacture: 2020, service_owner: "PTSC", image_file: "toyota.jpg" },
  { make: "Toyota", model: "Hilux", vehicle_type: "Truck", license_plate: "TOY-456", registration_number: "REG456", chassis_number: "CH456", serial_number: "SN456", year_of_manufacture: 2021, service_owner: "Fire Service", image_file: "Toyota.jpeg" }
]

vehicles = vehicle_data.map do |attrs|
  image_file = attrs.delete(:image_file)
  vehicle = Vehicle.create!(attrs)

  image_path = Rails.root.join("app/assets/images/placeholders/#{image_file}")
  if File.exist?(image_path)
    vehicle.image.attach(
      io: File.open(image_path),
      filename: image_file
    )
    puts "Attached image #{image_file} to #{vehicle.make} #{vehicle.model}"
  else
    puts "Image #{image_file} not found for #{vehicle.make} #{vehicle.model}"
  end

  vehicle
end

puts "Seeding drivers..."
drivers = [
  { name: "Frank", license_number: "HBC-2054", phone: "2964764" },
  { name: "Sean", license_number: "PDC-7547", phone: "7647454" },
  { name: "John", license_number: "PAZ-9045", phone: "7021921" }
].map { |d| Driver.create!(d) }

puts "Seeding trips..."
now = Time.current
trips_data = [
  { vehicle: vehicles[0], driver: drivers[1], start_time: now - 2.hours, end_time: now - 1.hour, distance_km: 100 },
  { vehicle: vehicles[0], driver: drivers[2], start_time: now - 3.hours, end_time: now - 2.hours, distance_km: 80 },
  { vehicle: vehicles[1], driver: drivers[2], start_time: now - 2.hours, end_time: now - 1.hour, distance_km: 50 }
]

trips_data.each { |trip_attrs| Trip.create!(trip_attrs) }

puts "Seeding complete!"
puts "You can log in with these users:"
users.each { |u| puts "Email: #{u.email} | Password: password123" }
