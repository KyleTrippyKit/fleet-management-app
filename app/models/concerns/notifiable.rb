# Add to app/models/concerns/notifiable.rb
module Notifiable
  extend ActiveSupport::Concern
  
  included do
    has_many :notifications, as: :recipient
  end
  
  def send_alert(message, type: :info)
    # Mock SMS/Email notification
    Rails.logger.info "ALERT: #{message}"
  end
end