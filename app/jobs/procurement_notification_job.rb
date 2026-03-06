# app/jobs/procurement_notification_job.rb
# Renamed from billing_notification_job to procurement_notification_job

class ProcurementNotificationJob < ApplicationJob
  queue_as :default

  def perform(inspection_id)
    inspection = Inspection.find(inspection_id)
    procurement_team = User.with_role(:procurement, inspection.vehicle.agency)

    procurement_team.each do |procurement_user|
      # Create in-app notification
      Notification.create!(
        user: procurement_user,
        title: "Inspection Ready for Procurement Review",
        message: "Inspection for #{inspection.vehicle.license_plate} needs RFQ creation.",
        notifiable: inspection,
        action_url: "/vmcott/procurement/dashboard"
      )
      
      # Send email if ProcurementMailer exists
      if defined?(ProcurementMailer)
        ProcurementMailer.notify(procurement_user, inspection).deliver_later
      end
    end
  end
end