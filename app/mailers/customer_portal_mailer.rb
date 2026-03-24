# app/mailers/customer_portal_mailer.rb
class CustomerPortalMailer < ApplicationMailer
  default from: 'VMCOTT <no-reply@vmcott.com>'

  def invitation(reception)
    @reception = reception
    @customer = reception.customer_display_info
    @portal_url = reception.portal_login_url
    @vmcott_phone = "868-625-1234"
    @vmcott_email = "service@vmcott.com"
    @vmcott_address = "Golden Grove Road, Piarco, Trinidad"
    
    mail(
      to: @reception.customer_email,
      subject: "Your Vehicle Repair Portal - VMCOTT"
    )
  end

  def recovery(reception)
    @reception = reception
    @customer = reception.customer_display_info
    @portal_url = reception.portal_login_url
    @vmcott_phone = "868-625-1234"
    @vmcott_email = "service@vmcott.com"
    
    mail(
      to: @reception.customer_email,
      subject: "Your Vehicle Repair Portal Access - VMCOTT"
    )
  end
end