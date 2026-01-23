require "test_helper"

class InvoiceAgingControllerTest < ActionDispatch::IntegrationTest
  test "should get report" do
    get invoice_aging_report_url
    assert_response :success
  end
end
