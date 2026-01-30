# app/jobs/low_stock_notification_job.rb
class LowStockNotificationJob < ApplicationJob
  queue_as :default

  def perform(part_id)
    part = Part.find_by(id: part_id)
    return unless part
    
    # Only notify if stock is actually low
    return unless part.current_stock <= part.reorder_point
    
    # Send email notification if configured
    if defined?(InventoryMailer) && InventoryMailer.respond_to?(:low_stock_alert)
      InventoryMailer.low_stock_alert(part).deliver_later
    end
    
    # Create notification for VMCOTT users if Notification model exists
    if defined?(Notification)
      User.where(agency: Agency.find_by(code: 'VMCOTT')).each do |user|
        Notification.create!(
          user: user,
          title: "Low Stock Alert: #{part.name}",
          message: "Stock: #{part.current_stock}, Minimum: #{part.minimum_stock}",
          link: Rails.application.routes.url_helpers.part_path(part),
          priority: part.current_stock <= 0 ? 'high' : 'medium'
        )
      end
    end
  end
end
