require "test_helper"

class ScannerHomeControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get scanner_home_index_url
    assert_response :success
  end
end
