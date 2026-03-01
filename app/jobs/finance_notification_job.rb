class FinanceNotificationJob < ApplicationJob
  queue_as :default

  def perform(inspection_id)
    inspection = Inspection.find(inspection_id)
    finance_team = User.with_role(:finance, inspection.vehicle.agency)

    finance_team.each do |finance_user|
      # Create in-app notification
      Notification.create!(
        user: finance_user,
        title: "Purchase Order Needs Finance Review",
        message: "PO for inspection #{inspection.vehicle.license_plate} needs finance approval.",
        notifiable: inspection,
        action_url: "/finance/dashboard"
      )
      
      # Send email if FinanceMailer exists
      if defined?(FinanceMailer)
        FinanceMailer.notify(finance_user, inspection).deliver_later
      end
    end
  end
end