# app/mailers/maintenance_mailer.rb
class MaintenanceMailer < ApplicationMailer
  def notify_store(maintenance)
    @maintenance = maintenance
    mail(to: "store@example.com", subject: "Maintenance Part Request")
  end
end
