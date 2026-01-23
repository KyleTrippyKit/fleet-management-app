require "test_helper"

class AccountingDashboardControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get accounting_dashboard_index_url
    assert_response :success
  end
end
