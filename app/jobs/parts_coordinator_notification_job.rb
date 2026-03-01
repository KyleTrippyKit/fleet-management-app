class PartsCoordinatorNotificationJob < ApplicationJob
  queue_as :default

  def perform(inspection_id)
    inspection = Inspection.find(inspection_id)
    coordinators = User.with_role(:parts_coordinator, inspection.vehicle.agency)

    coordinators.each do |coordinator|
      # Create in-app notification
      Notification.create!(
        user: coordinator,
        title: "New Inspection Needs Parts Review",
        message: "Inspection for #{inspection.vehicle.license_plate} has #{inspection.parts_requests.count} parts that need checking.",
        notifiable: inspection,
        action_url: "/vmcott/parts_coordinator/dashboard"
      )
      
      # Send email if PartsCoordinatorMailer exists
      if defined?(PartsCoordinatorMailer)
        PartsCoordinatorMailer.notify(coordinator, inspection).deliver_later
      end
    end
  end
end