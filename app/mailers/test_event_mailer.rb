# app/mailers/test_event_mailer.rb
class TestEventMailer < ApplicationMailer
  def event_notification(event)
    @event = event
    mail(to: "admin@example.com", subject: "Event Processed: #{event.event_type}")
  end
end