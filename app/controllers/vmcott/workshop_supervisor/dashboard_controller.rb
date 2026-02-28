# app/controllers/vmcott/workshop_supervisor/dashboard_controller.rb
class Vmcott::WorkshopSupervisor::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_workshop_supervisor

  def index
    @active_jobs = InternalPos.where(status: 'in_progress').count if defined?(InternalPos)
    @pending_jobs = InternalPos.where(status: 'pending').count if defined?(InternalPos)
    @completed_today = InternalPos.where(status: 'completed').where('updated_at >= ?', Date.current.beginning_of_day).count if defined?(InternalPos)
    
    # Automatically looks for: app/views/vmcott/workshop_supervisor/dashboard/index.html.erb
  end

  private

  def require_workshop_supervisor
    unless current_user.maintenance_supervisor? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Workshop Supervisor access only."
    end
  end
end