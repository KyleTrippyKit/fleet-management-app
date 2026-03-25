class FollowUpReminderJob < ApplicationJob
  queue_as :default
  
  def perform(quotation_id)
    quotation = Quotation.find(quotation_id)
    
    # Scenario 9: No response
    if quotation.status == 'sent' && quotation.sent_at < 3.days.ago
      # Send reminder
      Notification.create!(
        title: "Quotation pending approval",
        message: "Quotation ##{quotation.quote_number} is still waiting for your approval",
        link: "/customer/quotation/#{quotation.id}",
        user_id: quotation.client&.user_id
      )
      
      # Check if we've sent too many reminders
      reminder_count = quotation.reminders_sent || 0
      if reminder_count >= 3
        quotation.update!(status: :expired)
        quotation.inspection.update!(
          status: :on_hold,
          hold_reason: 'Quotation expired without approval'
        )
      else
        quotation.update!(reminders_sent: reminder_count + 1)
        # Schedule next reminder in 3 days
        self.class.set(wait: 3.days).perform_later(quotation_id)
      end
    end
  end
end