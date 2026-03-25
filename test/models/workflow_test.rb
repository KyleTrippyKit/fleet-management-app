require "test_helper"

class WorkflowTest < ActiveSupport::TestCase
  setup do
    # Create fresh test data with valid Trinidad license plate format
    @agency = create_test_agency
    @vehicle = create_test_vehicle("PBC-1234")  # Valid Trinidad format
    @inspector = create_test_user("inspector", "inspector@workflow.com")
    @inspection = create_test_inspection(@vehicle, @inspector)
    @workflow = WorkflowManager.new(@inspection)
    
    # Set Current.user for the workflow
    Current.user = @inspector
  end

  teardown do
    Current.user = nil
    # Clean up in reverse order to avoid foreign key issues
    Inspection.destroy_all
    Vehicle.destroy_all
    User.where(agency: @agency).destroy_all
    Agency.destroy_all
  end

  test "basic test - framework works" do
    assert true, "Test framework is working"
    assert @inspection.persisted?, "Inspection was created"
    assert @vehicle.persisted?, "Vehicle was created"
    assert @inspector.persisted?, "Inspector was created"
  end

  test "scenario_1_walkin_customer_intake" do
    params = {
      client_type: 'walkin',
      payment_terms: 'cash',
      customer_name: 'John Doe',
      visitor_name: 'John Doe',  # Added this
      driver_name: 'John Doe',   # Added this
      customer_phone: '868-123-4567',
      customer_email: 'john@example.com',
      expected_pickup_date: 3.days.from_now.to_date
    }
    
    @workflow.intake_vehicle(params)
    @inspection.reload
    
    assert_equal 'pending_inspection', @inspection.status
    assert_equal 'walkin', @inspection.client_type
    assert_equal 'cash', @inspection.payment_terms
    assert @inspection.received_at.present?, "received_at should be set"
    assert @inspection.reception_logs.exists?, "Reception log should be created"
  end
end
