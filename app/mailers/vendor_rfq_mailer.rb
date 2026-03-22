# app/mailers/vendor_rfq_mailer.rb
class VendorRfqMailer < ApplicationMailer
  default from: 'procurement@vmcott.com'

  def send_rfq_to_supplier(vendor_rfq, vendor_quotation, supplier)
    @vendor_rfq = vendor_rfq
    @vendor_quotation = vendor_quotation
    @supplier = supplier
    @rfq_items = vendor_rfq.vendor_rfq_items
    
    # Get vehicle info (make and model only, not license plate)
    @vehicle = vendor_rfq.vehicle
    @vehicle_info = if @vehicle.present?
      {
        make: @vehicle.make,
        model: @vehicle.model,
        year: @vehicle.year_of_manufacture
      }
    else
      nil
    end

    # Get the first item for the subject
    first_item = @rfq_items.first
    subject = "RFQ ##{vendor_rfq.rfq_number} - #{first_item.part&.name || first_item.custom_part_name}"

    mail(
      to: supplier.email,
      subject: subject,
      reply_to: 'procurement@vmcott.com'
    )
  end
end