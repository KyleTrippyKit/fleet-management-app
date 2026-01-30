class QuotationMailer < ApplicationMailer
  def quotation_submitted(quotation)
    @quotation = quotation

    recipients = []
    if quotation.agency&.respond_to?(:users)
      recipients.concat(quotation.agency.users.pluck(:email))
    end

    mail(
      to: recipients.uniq.presence || 'no-reply@vmcott.local',
      subject: "Quotation Received: #{quotation.quote_number}"
    )
  end
end