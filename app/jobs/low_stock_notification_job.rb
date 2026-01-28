# app/jobs/low_stock_notification_job.rb
class LowStockNotificationJob < ApplicationJob
  queue_as :default

  def perform
    low_stock_parts = Part.below_reorder_point
    
    low_stock_parts.each do |part|
      # Send email notification
      InventoryMailer.low_stock_alert(part).deliver_later
      
      # Create notification for VMCOTT users
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