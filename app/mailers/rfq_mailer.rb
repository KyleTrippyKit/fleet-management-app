class RfqMailer < ApplicationMailer
  def rfq_created(rfq)
    @rfq = rfq
    @agency = rfq.requesting_agency
    
    mail(
      to: @agency.email.presence || 'vmcott@example.com',
      cc: 'vmcott@example.com',
      subject: "New RFQ Created: #{rfq.rfq_number}"
    )
  end
  
  def status_changed(rfq)
    @rfq = rfq
    @agency = rfq.requesting_agency
    
    # Determine recipient based on status
    recipient_email = if @rfq.status == 'submitted'
                       'vmcott@example.com'
                     else
                       @agency.email.presence || 'vmcott@example.com'
                     end
    
    mail(
      to: recipient_email,
      subject: "RFQ Status Updated: #{rfq.rfq_number} - #{rfq.status.humanize}"
    )
  end
end
