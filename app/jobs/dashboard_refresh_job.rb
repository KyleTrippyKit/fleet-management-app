# app/jobs/dashboard_refresh_job.rb
class DashboardRefreshJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    # Calculate updated counts
    counts = {
      unread_notifications: Notification.where(user: user, read_at: nil).count,
      timestamp: Time.current.to_i
    }

    # Add role-specific counts
    if user.agency&.code == 'VMCOTT'
      if user.inspector?
        counts[:pending_inspections] = Inspection.where(status: 'pending_inspection').count
        counts[:qc_pending] = Inspection.where(status: 'ready_for_qc').count
      end
      
      if user.inventory_manager?
        counts[:pending_parts] = PartsRequest.where(status: 'pending').count
      end
      
      if user.mechanic?
        counts[:available_jobs] = InspectionJob.where(assigned_mechanic_id: nil, completed_at: nil).count
      end
    end

    # Broadcast updated counts
    DashboardChannel.broadcast_to("dashboard_#{user_id}", counts)
  end
end