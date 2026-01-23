# app/mailers/quotation_mailer.rb
class QuotationMailer < ApplicationMailer
  def quotation_sent(quotation, recipient)
    @quotation = quotation
    @recipient = recipient
    @agency = quotation.rfq&.requesting_agency
    @rfq = quotation.rfq
    
    subject = "New Quotation #{@quotation.quote_number} from VMCOTT"
    
    mail(
      to: @recipient.email,
      subject: subject,
      cc: 'quotations@vmcott.gov.tt'
    )
  end
end