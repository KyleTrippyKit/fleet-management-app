require "test_helper"

class SimpleTest < ActiveSupport::TestCase
  test "create reception log directly" do
    # Create test data
    agency = Agency.create!(name: "Test Agency", code: "TEST")
    vehicle = Vehicle.create!(
      license_plate: "ABC-1234",
      make: "Toyota",
      model: "Corolla",
      year_of_manufacture: 2020,
      vehicle_type: "Sedan",
      chassis_number: "CHAS123",
      serial_number: "SER123",
      status: "active",
      agency: agency
    )
    user = User.create!(
      email: "test@test.com",
      password: "password123",
      role: "inspector",
      name: "Test User",
      agency: agency
    )
    
    # Create reception log with ALL required fields
    log = ReceptionLog.create!(
      vehicle: vehicle,
      user_id: user.id,
      visitor_name: "John Doe",        # Required by database
      driver_name: "John Doe",         # Required by validation
      check_in_time: Time.current,
      condition_status: 'pending'
    )
    
    assert log.persisted?
    puts "Success! ReceptionLog created with id: #{log.id}"
  end
end
