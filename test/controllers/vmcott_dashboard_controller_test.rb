require "test_helper"

class VmcottDashboardControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get vmcott_dashboard_index_url
    assert_response :success
  end
end
