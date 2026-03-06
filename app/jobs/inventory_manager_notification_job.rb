# app/jobs/inventory_manager_notification_job.rb
# Renamed from parts_coordinator_notification_job to inventory_manager_notification_job

class InventoryManagerNotificationJob < ApplicationJob
  queue_as :default

  def perform(inspection_id)
    inspection = Inspection.find(inspection_id)
    inventory_managers = User.with_role(:inventory_manager, inspection.vehicle.agency)

    inventory_managers.each do |inventory_manager|
      # Create in-app notification
      Notification.create!(
        user: inventory_manager,
        title: "New Inspection Needs Parts Review",
        message: "Inspection for #{inspection.vehicle.license_plate} has #{inspection.parts_requests.count} parts that need checking.",
        notifiable: inspection,
        action_url: "/vmcott/inventory_manager/dashboard"
      )
      
      # Send email if InventoryManagerMailer exists
      if defined?(InventoryManagerMailer)
        InventoryManagerMailer.notify(inventory_manager, inspection).deliver_later
      end
    end
  end
end