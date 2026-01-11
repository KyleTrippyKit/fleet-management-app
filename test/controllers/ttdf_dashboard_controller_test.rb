require "test_helper"

class TtdfDashboardControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get ttdf_dashboard_index_url
    assert_response :success
  end
end
