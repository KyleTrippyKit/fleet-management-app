require "test_helper"

class StockLevelsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get stock_levels_index_url
    assert_response :success
  end

  test "should get update_batch" do
    get stock_levels_update_batch_url
    assert_response :success
  end
end
