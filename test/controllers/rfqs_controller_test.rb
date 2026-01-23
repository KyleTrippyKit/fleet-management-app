require "test_helper"

class RfqsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get rfqs_index_url
    assert_response :success
  end

  test "should get sent" do
    get rfqs_sent_url
    assert_response :success
  end

  test "should get show" do
    get rfqs_show_url
    assert_response :success
  end

  test "should get new" do
    get rfqs_new_url
    assert_response :success
  end

  test "should get create" do
    get rfqs_create_url
    assert_response :success
  end
end
