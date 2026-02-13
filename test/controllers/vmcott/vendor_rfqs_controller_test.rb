require "test_helper"

class Vmcott::VendorRfqsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get vmcott_vendor_rfqs_index_url
    assert_response :success
  end

  test "should get show" do
    get vmcott_vendor_rfqs_show_url
    assert_response :success
  end

  test "should get new" do
    get vmcott_vendor_rfqs_new_url
    assert_response :success
  end

  test "should get create" do
    get vmcott_vendor_rfqs_create_url
    assert_response :success
  end
end
