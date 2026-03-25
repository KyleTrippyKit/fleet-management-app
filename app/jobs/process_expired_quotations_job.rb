class ProcessExpiredQuotationsJob < ApplicationJob
  queue_as :default
  
  def perform
    # Scenario 9: Auto-expire quotations
    Quotation.where(status: 'sent')
             .where('valid_to < ?', Date.current)
             .find_each do |quotation|
      quotation.update!(status: :expired)
      
      Notification.create!(
        title: "Quotation expired",
        message: "Quotation ##{quotation.quote_number} has expired",
        link: "/vmcott/procurement/quotation/#{quotation.id}",
        user_id: User.where(role: 'procurement').pluck(:id)
      )
      
      quotation.inspection.update!(
        status: :on_hold,
        hold_reason: 'Quotation expired without approval'
      )
    end
  end
end