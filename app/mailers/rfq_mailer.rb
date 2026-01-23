class RfqMailer < ApplicationMailer
  def rfq_created(rfq)
    @rfq = rfq
    @agency = rfq.requesting_agency
    
    mail(
      to: @agency.email,  # Agency contact
      cc: 'vmcott@example.com',  # VMCOTT
      subject: "New RFQ Created: #{rfq.rfq_number}"
    )
  end
  
  def status_changed(rfq)
    @rfq = rfq
    @agency = rfq.requesting_agency
    
    mail(
      to: @rfq.status == 'submitted' ? 'vmcott@example.com' : @agency.email,
      subject: "RFQ Status Updated: #{rfq.rfq_number} - #{rfq.status.humanize}"
    )
  end
end