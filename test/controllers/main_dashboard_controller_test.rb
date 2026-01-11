require "test_helper"

class MainDashboardControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get main_dashboard_index_url
    assert_response :success
  end
end
