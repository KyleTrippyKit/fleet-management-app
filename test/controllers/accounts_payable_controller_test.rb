require "test_helper"

class AccountsPayableControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get accounts_payable_index_url
    assert_response :success
  end
end
