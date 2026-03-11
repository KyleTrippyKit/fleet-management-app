# app/controllers/vmcott/base_dashboard_controller.rb
class Vmcott::BaseDashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :set_notification_counts
  
  private
  
  def set_notification_counts
    @unread_notifications_count = Notification.where(user: current_user, read: false).count
    @pending_tasks_count = calculate_pending_tasks
  end
  
  def calculate_pending_tasks
    case current_user.role
    when 'security_gate_officer'
      VehicleConditionReport.where(status: 'draft').count
    when 'inspector'
      Inspection.where(status: 'pending_inspection').count
    # ... etc
    end
  end
end