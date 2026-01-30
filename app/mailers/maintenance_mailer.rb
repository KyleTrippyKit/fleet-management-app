class MaintenanceMailer < ApplicationMailer
  def notify_store(maintenance)
    @maintenance = maintenance

    recipients = []
    agency = maintenance.vehicle&.agency
    if agency&.respond_to?(:users)
      recipients.concat(agency.users.pluck(:email))
    end

    mail(
      to: recipients.uniq.presence || 'no-reply@vmcott.local',
      subject: "Maintenance Notification: #{maintenance.vehicle&.license_plate || 'Vehicle'}"
    )
  end
end