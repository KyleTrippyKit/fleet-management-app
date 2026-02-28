# app/jobs/invoice_reminder_job.rb
class InvoiceReminderJob < ApplicationJob
  queue_as :default
  
  def perform
    Rails.logger.info "🚀 Running InvoiceReminderJob at #{Time.current}"
    
    # Send reminders for newly overdue invoices
    newly_overdue = Invoice.overdue_scope.where('due_date = ?', Date.yesterday)
    
    newly_overdue.each do |invoice|
      send_overdue_reminder(invoice)
    end
    
    # Send weekly digest for long-overdue invoices (every Monday)
    if Date.current.monday?
      send_weekly_digest
    end
    
    Rails.logger.info "✅ InvoiceReminderJob completed"
  end
  
  private
  
  def send_overdue_reminder(invoice)
    # Skip if already reminded in last 7 days
    if invoice.respond_to?(:last_reminder_sent_at) && invoice.last_reminder_sent_at && invoice.last_reminder_sent_at > 7.days.ago
      Rails.logger.info "⏭️ Skipping invoice #{invoice.invoice_number} - already reminded recently"
      return
    end
    
    # Find recipient (created_by or agency finance user)
    recipient = invoice.created_by || invoice.agency&.users&.find_by(role: 'finance')
    
    unless recipient&.email
      Rails.logger.warn "⚠️ No recipient found for invoice #{invoice.invoice_number}"
      return
    end
    
    # Send email
    InvoiceMailer.overdue_reminder(invoice, recipient).deliver_later
    
    # Update reminder timestamp if column exists
    if invoice.respond_to?(:last_reminder_sent_at=)
      invoice.update_columns(last_reminder_sent_at: Time.current)
    end
    
    # Add note to invoice
    invoice.notes = invoice.notes.to_s + "\n[#{Date.current}] Overdue reminder sent to #{recipient.email}"
    invoice.save(validate: false)
    
    Rails.logger.info "📧 Overdue reminder sent for invoice #{invoice.invoice_number} to #{recipient.email}"
  end
  
  def send_weekly_digest
    # Group overdue invoices by agency
    overdue_by_agency = Invoice.overdue_scope
                               .where('due_date < ?', 7.days.ago)
                               .group_by(&:agency)
    
    overdue_by_agency.each do |agency, invoices|
      next unless agency
      
      # Find finance users
      recipients = User.where(agency: agency, role: ['finance', 'admin'])
      next if recipients.empty?
      
      # Send digest
      InvoiceMailer.weekly_overdue_digest(agency, invoices, recipients).deliver_later
      
      Rails.logger.info "📧 Weekly overdue digest sent to #{agency.code} for #{invoices.count} invoices"
    end
  end
end