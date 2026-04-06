require "test_helper"

class CustomerMailerTest < ActionMailer::TestCase
  test "vehicle_ready" do
    mail = CustomerMailer.vehicle_ready
    assert_equal "Vehicle ready", mail.subject
    assert_equal [ "to@example.org" ], mail.to
    assert_equal [ "from@example.com" ], mail.from
    assert_match "Hi", mail.body.encoded
  end

  test "quotation_ready" do
    mail = CustomerMailer.quotation_ready
    assert_equal "Quotation ready", mail.subject
    assert_equal [ "to@example.org" ], mail.to
    assert_equal [ "from@example.com" ], mail.from
    assert_match "Hi", mail.body.encoded
  end

  test "status_update" do
    mail = CustomerMailer.status_update
    assert_equal "Status update", mail.subject
    assert_equal [ "to@example.org" ], mail.to
    assert_equal [ "from@example.com" ], mail.from
    assert_match "Hi", mail.body.encoded
  end
end
