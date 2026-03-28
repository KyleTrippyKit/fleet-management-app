# app/controllers/admin/event_dashboard_controller.rb
class Admin::EventDashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin
  
  def index
    @pending_events = EventOutbox.where(status: 'pending').count
    @processing_events = EventOutbox.where(status: 'processing').count
    @failed_events = EventOutbox.where(status: 'failed').count
    @processed_events = EventOutbox.where(status: 'completed').count
    
    @recent_events = EventOutbox.order(created_at: :desc).limit(50)
    @dead_letters = DeadLetterQueue.where(resolved: false).order(created_at: :desc).limit(20)
  end
  
  def retry_failed
    event = EventOutbox.find(params[:id])
    event.update!(status: 'pending', retry_count: 0, error_message: nil)
    ProcessEventOutboxJob.perform_later
    redirect_to admin_event_dashboard_path, notice: "Event queued for retry"
  end
  
  private
  
  def require_admin
    unless current_user.admin?
      redirect_to root_path, alert: "Access denied"
    end
  end
end