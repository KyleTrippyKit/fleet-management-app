# app/mailers/customer_mailer.rb
class CustomerMailer < ApplicationMailer
  default from: "VMCOTT Service <notifications@vmcott.com>"
  
  # Base URL for customer portal
  helper_method :customer_portal_url

  def vehicle_ready(inspection, customer_email, customer_name = nil)
    @inspection = inspection
    @vehicle = inspection.vehicle
    @customer_name = customer_name || "Valued Customer"
    @pickup_code = inspection.pickup_code || generate_pickup_code(inspection)
    @vmcott_phone = "868-625-1234"
    @vmcott_address = "Golden Grove Road, Piarco, Trinidad"
    @portal_url = customer_portal_url
    
    mail(
      to: customer_email,
      subject: "✅ Your vehicle is ready for pickup - #{@vehicle.license_plate}"
    )
  end

  def quotation_ready(inspection, customer_email, customer_name = nil, token = nil)
    @inspection = inspection
    @vehicle = inspection.vehicle
    @customer_name = customer_name || "Valued Customer"
    @quotation = inspection.latest_quotation
    @portal_url = customer_portal_url(token)
    
    mail(
      to: customer_email,
      subject: "📄 Your repair quotation is ready - #{@vehicle.license_plate}"
    )
  end

  def status_update(inspection, customer_email, old_status, new_status, customer_name = nil)
    @inspection = inspection
    @vehicle = inspection.vehicle
    @customer_name = customer_name || "Valued Customer"
    @old_status = old_status
    @new_status = new_status
    @portal_url = customer_portal_url
    @status_descriptions = {
      'inspected' => 'Initial inspection completed',
      'diagnosed' => 'Diagnosis complete',
      'approved' => 'Work approved',
      'in_progress' => 'Work in progress',
      'qc_pending' => 'Quality control in progress',
      'ready_for_pickup' => 'Ready for pickup',
      'completed' => 'Service completed'
    }
    
    mail(
      to: customer_email,
      subject: "🔄 Your vehicle status has been updated - #{@vehicle.license_plate}"
    )
  end

  def qc_passed(inspection, customer_email, customer_name = nil)
    @inspection = inspection
    @vehicle = inspection.vehicle
    @customer_name = customer_name || "Valued Customer"
    @pickup_code = inspection.pickup_code || generate_pickup_code(inspection)
    @vmcott_phone = "868-625-1234"
    @vmcott_address = "Golden Grove Road, Piarco, Trinidad"
    @portal_url = customer_portal_url
    
    mail(
      to: customer_email,
      subject: "✅ QC Passed - Your vehicle is ready for pickup - #{@vehicle.license_plate}"
    )
  end

  private

  def customer_portal_url(token = nil)
    if token.present?
      "https://#{Rails.application.config.action_mailer.default_url_options[:host]}/customer/login?token=#{token}"
    else
      "https://#{Rails.application.config.action_mailer.default_url_options[:host]}/customer/login"
    end
  end

  def generate_pickup_code(inspection)
    "PK-#{inspection.id}-#{SecureRandom.hex(4).upcase}"
  end
end