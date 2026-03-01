class BillingNotificationJob < ApplicationJob
  queue_as :default

  def perform(inspection_id)
    inspection = Inspection.find(inspection_id)
    billing_team = User.with_role(:billing, inspection.vehicle.agency)

    billing_team.each do |billing_user|
      # Create in-app notification
      Notification.create!(
        user: billing_user,
        title: "Inspection Ready for Billing Review",
        message: "Inspection for #{inspection.vehicle.license_plate} needs billing approval.",
        notifiable: inspection,
        action_url: "/vmcott/billing/dashboard"
      )
      
      # Send email if BillingMailer exists
      if defined?(BillingMailer)
        BillingMailer.notify(billing_user, inspection).deliver_later
      end
    end
  end
end