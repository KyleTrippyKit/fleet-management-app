require "test_helper"

class WorkflowDebugTest < ActiveSupport::TestCase
  test "debug reception log creation" do
    # Create test data
    agency = create_test_agency
    vehicle = create_test_vehicle("PBC-1234")
    inspector = create_test_user("inspector", "inspector@debug.com")
    inspection = create_test_inspection(vehicle, inspector)
    
    # Set Current.user
    Current.user = inspector
    
    puts "Current.user: #{Current.user.inspect}"
    puts "Current.user.id: #{Current.user.id}"
    
    # Try to create ReceptionLog directly
    log = ReceptionLog.create!(
      vehicle: vehicle,
      user_id: Current.user.id,
      check_in_time: Time.current,
      condition_status: 'pending'
    )
    
    assert log.persisted?
    puts "ReceptionLog created successfully with id: #{log.id}"
  end
end
