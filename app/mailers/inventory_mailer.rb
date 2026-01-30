class InvoiceMailer < ApplicationMailer
  def invoice_created(invoice)
    @invoice = invoice

    recipients = []
    if invoice.respond_to?(:agency) && invoice.agency&.respond_to?(:users)
      recipients.concat(invoice.agency.users.pluck(:email))
    end

    mail(
      to: recipients.uniq.presence || 'no-reply@vmcott.local',
      subject: "Invoice Created: #{invoice.invoice_number}"
    )
  end
end