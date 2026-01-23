require "test_helper"

class PaymentDashboardControllerTest < ActionDispatch::IntegrationTest
  test "should get bulk_payment" do
    get payment_dashboard_bulk_payment_url
    assert_response :success
  end
end
