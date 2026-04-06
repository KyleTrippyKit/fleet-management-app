# app/services/sms_service.rb
class SmsService
  def self.send_sms(to_number, message)
    return unless Rails.env.production? || ENV['SMS_ENABLED'] == 'true'
    
    client = Twilio::REST::Client.new(
      ENV['TWILIO_ACCOUNT_SID'],
      ENV['TWILIO_AUTH_TOKEN']
    )
    
    client.messages.create(
      from: ENV['TWILIO_PHONE_NUMBER'],
      to: to_number,
      body: message
    )
  rescue => e
    Rails.logger.error "SMS Error: #{e.message}"
  end
  
  def self.vehicle_ready(vehicle, phone_number, pickup_code)
    message = "VMCOTT: Your vehicle #{vehicle.license_plate} is ready for pickup. Code: #{pickup_code}. Visit us at Golden Grove Road, Piarco."
    send_sms(phone_number, message)
  end
  
  def self.quotation_ready(vehicle, phone_number, amount)
    message = "VMCOTT: Your repair estimate for #{vehicle.license_plate} is ready. Amount: $#{amount}. View at vmcott.com/customer/login"
    send_sms(phone_number, message)
  end
  
  def self.status_update(vehicle, phone_number, status)
    message = "VMCOTT: Your vehicle #{vehicle.license_plate} status: #{status}. Track at vmcott.com/customer/login"
    send_sms(phone_number, message)
  end
end