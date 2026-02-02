# db/seeds/ptsc_vehicles.rb
# Usage:
#   bin/rails runner db/seeds/ptsc_vehicles.rb

require "securerandom"

ptsc = Agency.find_by(code: "PTSC") || Agency.find_by(name: "PTSC")

if ptsc.nil?
  puts "❌ PTSC agency not found. Ensure agencies table has PTSC (code: PTSC)."
  exit 1
end

# Helper: short unique token
def short_token(len = 8)
  SecureRandom.hex(len / 2).upcase
end

vehicles_data = [
  { license_plate: "PTSC-001", make: "Hino",   model: "Blue Ribbon", year_of_manufacture: 2016, vehicle_type: "Bus",    fuel_type: "Diesel",   transmission: "Automatic", color: "White"  },
  { license_plate: "PTSC-002", make: "Hino",   model: "Blue Ribbon", year_of_manufacture: 2017, vehicle_type: "Bus",    fuel_type: "Diesel",   transmission: "Automatic", color: "White"  },
  { license_plate: "PTSC-003", make: "Isuzu",  model: "NQR",         year_of_manufacture: 2015, vehicle_type: "Bus",    fuel_type: "Diesel",   transmission: "Manual",    color: "White"  },

  { license_plate: "PTSC-010", make: "Toyota", model: "Hiace",       year_of_manufacture: 2018, vehicle_type: "Van",    fuel_type: "Diesel",   transmission: "Automatic", color: "Silver" },
  { license_plate: "PTSC-011", make: "Nissan", model: "NV350",       year_of_manufacture: 2019, vehicle_type: "Van",    fuel_type: "Diesel",   transmission: "Automatic", color: "Silver" },

  { license_plate: "PTSC-020", make: "Toyota", model: "Hilux",       year_of_manufacture: 2020, vehicle_type: "Pickup", fuel_type: "Diesel",   transmission: "Automatic", color: "Red"    },
  { license_plate: "PTSC-021", make: "Nissan", model: "Navara",      year_of_manufacture: 2021, vehicle_type: "Pickup", fuel_type: "Diesel",   transmission: "Automatic", color: "Blue"   },

  { license_plate: "PTSC-030", make: "Toyota", model: "Corolla",     year_of_manufacture: 2017, vehicle_type: "Car",    fuel_type: "Gasoline", transmission: "Automatic", color: "Grey"   },
  { license_plate: "PTSC-031", make: "Nissan", model: "Sentra",      year_of_manufacture: 2018, vehicle_type: "Car",    fuel_type: "Gasoline", transmission: "Automatic", color: "Black"  }
]

created = 0
updated = 0

vehicles_data.each_with_index do |v, idx|
  record = Vehicle.find_or_initialize_by(agency_id: ptsc.id, license_plate: v[:license_plate])

  # Only generate these if missing (so re-running the seed doesn't change identity fields)
  record.chassis_number ||= "CHS-#{v[:license_plate]}-#{short_token(10)}"   # required by validation
  record.serial_number  ||= "SER-#{v[:license_plate]}-#{short_token(10)}"   # required by validation

  # Optional but helpful identifiers
  record.registration_number ||= "REG-#{v[:license_plate]}"
  record.rfid_tag ||= "RFID-PTSC-#{(1000 + idx)}"

  record.assign_attributes(
    make: v[:make],
    model: v[:model],
    year_of_manufacture: v[:year_of_manufacture],
    vehicle_type: v[:vehicle_type],
    fuel_type: v[:fuel_type],
    transmission: v[:transmission],
    color: v[:color],
    status: "active"
  )

  if record.new_record?
    record.save!
    created += 1
  else
    if record.changed?
      record.save!
      updated += 1
    end
  end
end

puts "✅ PTSC Vehicles seeded for agency #{ptsc.name} (#{ptsc.code})"
puts "Created: #{created}, Updated: #{updated}, Total PTSC vehicles: #{Vehicle.where(agency_id: ptsc.id).count}"
