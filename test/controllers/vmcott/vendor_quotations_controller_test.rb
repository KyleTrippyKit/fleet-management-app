require "test_helper"

class Vmcott::VendorQuotationsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get vmcott_vendor_quotations_index_url
    assert_response :success
  end

  test "should get show" do
    get vmcott_vendor_quotations_show_url
    assert_response :success
  end

  test "should get new" do
    get vmcott_vendor_quotations_new_url
    assert_response :success
  end

  test "should get create" do
    get vmcott_vendor_quotations_create_url
    assert_response :success
  end
end
