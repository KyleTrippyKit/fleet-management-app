# app/services/sms_notification_service.rb
class SmsNotificationService
  def self.send(to, message)
    return unless Rails.env.production?
    
    # Uncomment when you have Twilio configured
    # client = Twilio::REST::Client.new(
    #   ENV['TWILIO_ACCOUNT_SID'],
    #   ENV['TWILIO_AUTH_TOKEN']
    # )
    # 
    # client.messages.create(
    #   from: ENV['TWILIO_PHONE_NUMBER'],
    #   to: to,
    #   body: message
    # )
    
    Rails.logger.info("SMS would be sent to #{to}: #{message}")
  end
end