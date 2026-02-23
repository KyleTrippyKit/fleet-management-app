# test/system/vmcott_workflow_test.rb
require "application_system_test_case"

class VmcottWorkflowTest < ApplicationSystemTestCase
  test "complete VMCOTT workflow" do
    visit purchase_orders_path
    click_on "Accept"
    assert_text "Work in Progress"
    click_on "Work Completed"
    assert_text "Ready for Delivery"
  end
end