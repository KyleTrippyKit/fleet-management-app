# app/controllers/notifications_controller.rb
class NotificationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_notification, only: [:show, :mark_as_read]

  def index
    @notifications = Notification.where(user: current_user)
                                 .order(created_at: :desc)
                                 .page(params[:page]).per(20)
  end

  def show
    @notification.mark_as_read! unless @notification.read?
    redirect_to @notification.action_url.presence || notifications_path
  end

  def mark_as_read
    @notification.update(read: true)
    respond_to do |format|
      format.html { redirect_back fallback_location: notifications_path }
      format.json { render json: { success: true } }
    end
  end

  def mark_all_as_read
    Notification.where(user: current_user, read: false).update_all(read: true)
    redirect_back fallback_location: notifications_path, notice: "All notifications marked as read."
  end

  private

  def set_notification
    @notification = Notification.find(params[:id])
    # Security check - ensure user owns this notification
    redirect_to notifications_path, alert: "Access denied." unless @notification.user_id == current_user.id
  end
end