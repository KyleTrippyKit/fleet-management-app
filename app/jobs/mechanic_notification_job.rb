class MechanicNotificationJob < ApplicationJob
  queue_as :default

  def perform(inspection_id)
    inspection = Inspection.find(inspection_id)
    mechanics = User.with_role(:mechanic, inspection.vehicle.agency)

    mechanics.each do |mechanic|
      # Create in-app notification
      Notification.create!(
        user: mechanic,
        title: "New Jobs Available",
        message: "Inspection for #{inspection.vehicle.license_plate} is ready for repair work.",
        notifiable: inspection,
        action_url: "/vmcott/mechanic/dashboard"
      )
      
      # Send email if MechanicMailer exists
      if defined?(MechanicMailer)
        MechanicMailer.notify(mechanic, inspection).deliver_later
      end
    end
  end
end