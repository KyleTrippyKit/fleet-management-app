# app/jobs/schedule_daily_reminders.rb
class ScheduleDailyRemindersJob < ApplicationJob
  queue_as :default
  
  def perform
    # Schedule daily reminders for:
    # - Pending client approvals (3 day reminder)
    # - Overdue payments
    # - Vehicles ready for pickup (daily reminder after 3 days)
    
    # Check for pending quotations
    Quotation.where(status: 'sent_to_client')
             .where('sent_at < ?', 3.days.ago)
             .where(reminders_sent: [nil, 0])
             .find_each do |quotation|
      ClientReminderMailer.quotation_pending(quotation).deliver_later
      quotation.update!(reminders_sent: 1)
    end
    
    # Check for quotations expiring in 24 hours
    Quotation.where(status: 'sent_to_client')
             .where('valid_until = ?', Date.current + 1.day)
             .find_each do |quotation|
      ClientReminderMailer.quotation_expiring_soon(quotation).deliver_later
    end
    
    # Check for overdue pickups
    Inspection.where(status: 'ready_for_pickup')
             .where('ready_for_pickup_at < ?', 3.days.ago)
             .find_each do |inspection|
      ClientReminderMailer.vehicle_ready_for_pickup(inspection).deliver_later
    end
  end
end