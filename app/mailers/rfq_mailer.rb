class RfqMailer < ApplicationMailer
  def rfq_created(rfq)
    @rfq = rfq
    mail(
      to: recipient_emails_for_rfq(rfq),
      subject: "RFQ Created: #{rfq.rfq_number}"
    )
  end

  def status_changed(rfq)
    @rfq = rfq
    mail(
      to: recipient_emails_for_rfq(rfq),
      subject: "RFQ Status Updated: #{rfq.rfq_number} (#{rfq.status.humanize})"
    )
  end

  # Sends the RFQ details to a specific email (used by rfqs_controller#send_email)
  def rfq_details(rfq, recipient_email)
    @rfq = rfq
    mail(
      to: recipient_email,
      subject: "RFQ Details: #{rfq.rfq_number}"
    )
  end

  private

  def recipient_emails_for_rfq(rfq)
    emails = []

    # Requesting agency notifications
    if rfq.requesting_agency.respond_to?(:users)
      emails.concat(rfq.requesting_agency.users.pluck(:email))
    end

    # Processing agency (VMCOTT) notifications
    if rfq.processing_agency&.respond_to?(:users)
      emails.concat(rfq.processing_agency.users.pluck(:email))
    end

    emails.uniq.presence || 'no-reply@vmcott.local'
  end
end