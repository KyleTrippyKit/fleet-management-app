# test/system/workflow_system_test.rb
require 'application_system_test_case'

class WorkflowSystemTest < ApplicationSystemTestCase
  setup do
    @vehicle = vehicles(:sedan)
    @inspector = users(:inspector)
    @mechanic = users(:mechanic)
  end

  test "complete walk-in customer journey" do
    # 1. Security officer logs in and checks in vehicle
    visit new_user_session_path
    fill_in 'Email', with: 'security@vmcott.com'
    fill_in 'Password', with: 'password123'
    click_button 'Sign in'
    
    visit vmcott_security_gate_officer_dashboard_path
    click_link 'Manual Entry'
    
    fill_in 'License Plate', with: @vehicle.license_plate
    fill_in 'Customer Name', with: 'John Doe'
    fill_in 'Customer Phone', with: '868-123-4567'
    click_button 'Receive Vehicle'
    
    assert_text 'Vehicle received successfully'
    
    # 2. Inspector performs inspection
    click_link 'Logout'
    visit new_user_session_path
    fill_in 'Email', with: @inspector.email
    fill_in 'Password', with: 'password123'
    click_button 'Sign in'
    
    visit vmcott_inspector_dashboard_path
    click_link 'New Inspection'
    
    select @vehicle.license_plate, from: 'Vehicle'
    fill_in 'Mileage', with: '50000'
    
    # Add a finding
    click_button 'Add Finding'
    fill_in 'Description', with: 'Brake pads worn'
    fill_in 'Labor Cost', with: '85'
    select 'High', from: 'Priority'
    click_button 'Complete Inspection'
    
    assert_text 'Inspection completed'
    
    # 3. Mechanic reviews and requests parts
    click_link 'Logout'
    visit new_user_session_path
    fill_in 'Email', with: @mechanic.email
    fill_in 'Password', with: 'password123'
    click_button 'Sign in'
    
    visit vmcott_mechanic_dashboard_path
    assert_text 'Pending Review'
    click_link 'Review'
    
    fill_in 'Labor Cost', with: '85'
    click_button 'Request Parts'
    
    # Add a part
    fill_in 'Part Name', with: 'Brake Pads'
    fill_in 'Quantity', with: '2'
    click_button 'Submit Request'
    
    assert_text 'Parts requested'
    
    # 4. Continue through the rest of the workflow...
    # (Similar steps for inventory manager, supervisor, procurement, client portal, etc.)
  end
end