require "test_helper"

class JobTemplatesControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get job_templates_index_url
    assert_response :success
  end
end
