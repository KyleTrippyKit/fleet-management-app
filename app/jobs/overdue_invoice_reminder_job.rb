# app/jobs/overdue_invoice_reminder_job.rb
class OverdueInvoiceReminderJob < ApplicationJob
  queue_as :default
  
  def perform
    # Find invoices that became overdue today
    newly_overdue = Invoice.where(status: 'overdue')
                          .where('due_date = ?', Date.yesterday)
    
    newly_overdue.each do |invoice|
      InvoiceMailer.reminder(invoice).deliver_later
      
      # Log the reminder
      Rails.logger.info "📧 Reminder sent for invoice #{invoice.invoice_number}"
      
      # Optional: Add a note to the invoice
      invoice.notes = invoice.notes.to_s + "\n[#{Time.current.strftime('%Y-%m-%d')}] Reminder email sent"
      invoice.save
    end
    
    # Send weekly digest for older overdue invoices
    if Date.current.monday? # Send every Monday
      old_overdue = Invoice.where(status: 'overdue')
                          .where('due_date < ?', 7.days.ago)
      
      old_overdue.group_by(&:agency).each do |agency, invoices|
        # Send digest email to finance team
        InvoiceMailer.weekly_overdue_digest(agency, invoices).deliver_later
      end
    end
  end
end