ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # DO NOT automatically load all fixtures - we'll create data manually
    # fixtures :all
    
    # Helper methods for creating test data
    def create_test_agency
      Agency.find_or_create_by!(code: "TEST") do |a|
        a.name = "Test Agency"
        a.code = "TEST"
        a.description = "Test Agency for Workflow Testing"
      end
    end
    
    def create_test_vehicle(license_plate = "ABC-1234")
      agency = create_test_agency
      Vehicle.create!(
        license_plate: license_plate,
        make: "Toyota",
        model: "Corolla",
        year_of_manufacture: 2020,
        vehicle_type: "Sedan",
        chassis_number: "CHAS#{license_plate.gsub('-', '')}",
        serial_number: "SER#{license_plate.gsub('-', '')}",
        status: "active",
        agency: agency
      )
    end
    
    def create_test_user(role = "inspector", email = nil)
      User.create!(
        email: email || "#{role}@test.com",
        password: "password123",
        role: role,
        name: "#{role.titleize} User",
        agency: create_test_agency
      )
    end
    
    def create_test_inspection(vehicle = nil, inspector = nil)
      vehicle ||= create_test_vehicle
      inspector ||= create_test_user("inspector")
      
      Inspection.create!(
        vehicle: vehicle,
        inspector: inspector,
        status: "pending_inspection",
        workflow_type: "work_before_payment",
        client_approval_status: "pending",
        payment_status: "pending"
      )
    end
  end
end
