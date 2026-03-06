# app/mailers/procurement_mailer.rb
# Renamed from billing_mailer to procurement_mailer

class ProcurementMailer < ApplicationMailer
  def notify(procurement_officer, parts_request)
    @procurement_officer = procurement_officer
    @parts_request = parts_request
    @inspection = parts_request.inspection
    @vehicle = @inspection&.vehicle
    
    mail(
      to: procurement_officer.email,
      subject: "RFQ Required for #{@vehicle&.license_plate || 'Vehicle'}"
    )
  end
  
  def rfq_created(procurement_officer, rfq)
    @procurement_officer = procurement_officer
    @rfq = rfq
    
    mail(
      to: procurement_officer.email,
      subject: "RFQ ##{rfq.rfq_number} Created"
    )
  end
  
  def quotation_received(procurement_officer, quotation)
    @procurement_officer = procurement_officer
    @quotation = quotation
    @rfq = quotation.vendor_rfq
    
    mail(
      to: procurement_officer.email,
      subject: "Quotation Received for RFQ ##{@rfq.rfq_number}"
    )
  end
end