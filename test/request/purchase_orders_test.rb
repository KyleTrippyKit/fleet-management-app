# test/requests/purchase_orders_test.rb
require "test_helper"

class PurchaseOrdersTest < ActionDispatch::IntegrationTest
  test "VMCOTT can accept PO" do
    post accept_entire_po_purchase_order_path(@po)
    assert_redirected_to purchase_order_path(@po)
    follow_redirect!
    assert_select ".alert", "Purchase order accepted successfully"
  end
end