# app/mailers/ptsc_mailer.rb
class PtscMailer < ApplicationMailer
  def vehicle_status_update(vehicle, admin_email)
    @vehicle = vehicle
    @status = vehicle.current_status
    mail(to: admin_email, subject: "Vehicle #{vehicle.license_plate} Status Update")
  end
end