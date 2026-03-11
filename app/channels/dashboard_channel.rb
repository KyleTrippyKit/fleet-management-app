# app/channels/dashboard_channel.rb
class DashboardChannel < ApplicationCable::Channel
  def subscribed
    stream_from "dashboard_#{current_user.id}"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end

  def refresh
    # Trigger a dashboard refresh
    DashboardRefreshJob.perform_later(current_user.id)
  end
end