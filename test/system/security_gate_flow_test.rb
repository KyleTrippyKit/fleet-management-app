# test/system/security_gate_flow_test.rb
class SecurityGateFlowTest < ApplicationSystemTestCase
  test "security gate officer can check in vehicle" do
    login_as users(:security_gate)
    
    visit vmcott_security_gate_officer_dashboard_path
    click_on "Manual Entry"
    
    fill_in "License Plate", with: "TEST-123"
    click_on "Search"
    
    assert_selector "#search-results", text: "TEST-123"
  end
end