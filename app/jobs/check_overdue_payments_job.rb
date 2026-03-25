class CheckOverduePaymentsJob < ApplicationJob
  queue_as :default
  
  def perform
    # Check for invoices due today or overdue
    Invoice.where(status: 'pending')
           .where('due_date <= ?', Date.current)
           .find_each do |invoice|
      
      invoice.update!(status: 'overdue')
      
      # Send notification
      Notification.create!(
        user: invoice.inspection.client.user,
        title: 'Payment overdue',
        message: "Invoice ##{invoice.invoice_number} is now overdue",
        link: "/customer/payments"
      )
      
      # Add late fee if configured
      if invoice.inspection.agency.settings.late_fee_enabled
        late_fee = invoice.amount * 0.05 # 5% late fee
        invoice.update!(late_fee: late_fee, total_due: invoice.amount + late_fee)
      end
    end
  end
end