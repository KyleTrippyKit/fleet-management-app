# app/mailers/invoice_mailer.rb
class InvoiceMailer < ApplicationMailer
  default from: 'notifications@vmcott.gov.tt'
  
  def overdue_reminder(invoice, recipient)
    @invoice = invoice
    @recipient = recipient
    @agency = invoice.agency
    
    mail(
      to: recipient.email,
      subject: "⚠️ OVERDUE: Invoice #{invoice.invoice_number} is #{invoice.days_overdue} days overdue"
    )
  end
  
  def weekly_overdue_digest(agency, invoices, recipients)
    @agency = agency
    @invoices = invoices
    @total_overdue = invoices.sum(&:amount)
    @oldest_invoice = invoices.min_by(&:due_date)
    
    mail(
      to: recipients.map(&:email),
      subject: "📊 Weekly Overdue Invoice Summary - #{agency.code}"
    )
  end
  
  def payment_confirmation(invoice, recipient)
    @invoice = invoice
    @recipient = recipient
    
    mail(
      to: recipient.email,
      subject: "✅ Payment Confirmed: Invoice #{invoice.invoice_number}"
    )
  end
end