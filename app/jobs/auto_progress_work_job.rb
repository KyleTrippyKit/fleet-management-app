# app/jobs/auto_progress_work_job.rb
class AutoProgressWorkJob < ApplicationJob
  queue_as :default
  
  def perform
    # Auto-start pending work orders that are older than 1 hour
    pending_orders = InternalPos.where(status: 'pending')
                                .where('created_at < ?', 1.hour.ago)
    
    pending_orders.each do |work_order|
      # Only auto-start workshop work, not QC or Billing
      if work_order.notes.to_s.include?('Workshop')
        work_order.update!(status: 'in_progress')
        Rails.logger.info "Auto-started work order #{work_order.work_order_number}"
      end
    end
    
    # Check for work that's been in progress too long
    stuck_work = InternalPos.where(status: 'in_progress')
                            .where('updated_at < ?', 3.days.ago)
    
    stuck_work.each do |work_order|
      NotificationService.notify_workshop(
        "Work order #{work_order.work_order_number} has been in progress for 3 days"
      )
    end
  end
end