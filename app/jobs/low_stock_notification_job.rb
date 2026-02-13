# app/jobs/low_stock_notification_job.rb
class LowStockNotificationJob < ApplicationJob
  queue_as :default

  def perform(part_id)
    part = Part.find_by(id: part_id)
    return unless part
    return unless part.current_stock <= part.reorder_point

    # Email
    InventoryMailer.low_stock_alert(part).deliver_later

    # Optional notifications
    return unless defined?(Notification)

    agency = Agency.find_by(code: "VMCOTT")
    return unless agency

    User.where(agency: agency).find_each do |user|
      Notification.create!(
        user: user,
        title: "Low Stock Alert: #{part.name}",
        message: "Stock: #{part.current_stock}, Reorder Point: #{part.reorder_point}",
        link: Rails.application.routes.url_helpers.part_path(part),
        priority: part.current_stock <= 0 ? "high" : "medium"
      )
    end
  end
end
