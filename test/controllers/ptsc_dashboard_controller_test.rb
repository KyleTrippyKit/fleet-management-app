require "test_helper"

class PtscDashboardControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get ptsc_dashboard_index_url
    assert_response :success
  end
end
