require "test_helper"

class TtpsDashboardControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get ttps_dashboard_index_url
    assert_response :success
  end
end
