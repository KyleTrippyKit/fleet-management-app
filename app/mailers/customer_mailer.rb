# app/mailers/customer_mailer.rb
class CustomerMailer < ApplicationMailer
  default from: "VMCOTT Service <notifications@vmcott.com>"

  def vehicle_ready(inspection, customer_email, customer_name = nil)
    @inspection = inspection
    @vehicle = inspection.vehicle
    @customer_name = customer_name || "Valued Customer"
    @pickup_code = inspection.pickup_code
    @vmcott_phone = "868-625-1234"
    @vmcott_address = "Golden Grove Road, Piarco, Trinidad"
    
    mail(
      to: customer_email,
      subject: "✅ Your vehicle is ready for pickup - #{@vehicle.license_plate}"
    )
  end

  def quotation_ready(inspection, customer_email, customer_name = nil)
    @inspection = inspection
    @vehicle = inspection.vehicle
    @customer_name = customer_name || "Valued Customer"
    @quotation = inspection.latest_quotation
    @portal_url = customer_login_url
    
    mail(
      to: customer_email,
      subject: "📄 Your repair quotation is ready - #{@vehicle.license_plate}"
    )
  end

  def status_update(inspection, customer_email, old_status, new_status)
    @inspection = inspection
    @vehicle = inspection.vehicle
    @old_status = old_status
    @new_status = new_status
    @portal_url = customer_login_url
    
    mail(
      to: customer_email,
      subject: "🔄 Your vehicle status has been updated - #{@vehicle.license_plate}"
    )
  end

  def qc_passed(inspection, customer_email, customer_name = nil)
    @inspection = inspection
    @vehicle = inspection.vehicle
    @customer_name = customer_name || "Valued Customer"
    @pickup_code = inspection.pickup_code
    @vmcott_phone = "868-625-1234"
    
    mail(
      to: customer_email,
      subject: "✅ QC Passed - Your vehicle is ready for pickup - #{@vehicle.license_plate}"
    )
  end
end