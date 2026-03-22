# app/controllers/notifications_controller.rb
class NotificationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_notification, only: [:show, :mark_as_read]

  def index
    @notifications = Notification.where(user: current_user)
                                 .order(created_at: :desc)
                                 .page(params[:page]).per(20)
    @unread_count = Notification.where(user: current_user, read: false).count  # Changed from read_at: nil to read: false
  end

  def show
    @notification.mark_as_read! unless @notification.read?  # This uses read? method which checks the read boolean
    redirect_to @notification.link.presence || notifications_path
  end

  def mark_as_read
    @notification.mark_as_read!
    
    respond_to do |format|
      format.html { redirect_back fallback_location: notifications_path, notice: 'Notification marked as read.' }
      format.json { render json: { success: true } }
      format.turbo_stream { render turbo_stream: turbo_stream.replace(@notification, partial: 'notifications/notification', locals: { notification: @notification }) }
    end
  end

  def mark_all_as_read
    Notification.where(user: current_user, read: false).update_all(read: true)  # Changed from read_at: nil to read: false, and read_at: Time.current to read: true
    redirect_back fallback_location: notifications_path, notice: "All notifications marked as read."
  end

  private

  def set_notification
    @notification = Notification.find(params[:id])
    # Security check - ensure user owns this notification
    redirect_to notifications_path, alert: "Access denied." unless @notification.user_id == current_user.id
  end
end