class SendDailyRemindersJob < ApplicationJob
  queue_as :default
  
  def perform
    # Send reminders for pending actions
    # 1. Pending quotations
    Quotation.where(status: 'sent_to_client')
             .where('sent_at < ?', 2.days.ago)
             .find_each do |quotation|
      Notification.create!(
        user: quotation.inspection.client.user,
        title: 'Action required',
        message: "Please approve or reject quotation ##{quotation.quote_number}",
        link: "/customer/quotation/#{quotation.id}"
      )
    end
    
    # 2. Vehicles ready for pickup
    Inspection.where(status: 'ready_for_pickup')
             .where('ready_for_pickup_at < ?', 1.day.ago)
             .find_each do |inspection|
      Notification.create!(
        user: inspection.client.user,
        title: 'Vehicle ready for pickup',
        message: "Your vehicle has been ready for #{days_ready} days. Please arrange pickup.",
        link: "/customer/dashboard"
      )
    end
  end
end