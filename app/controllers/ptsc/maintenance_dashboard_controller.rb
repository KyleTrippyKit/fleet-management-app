# app/controllers/ptsc/maintenance_dashboard_controller.rb
class Ptsc::MaintenanceDashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_ptsc_maintenance!
  
  def index
    # Get maintenance through vehicles instead of directly by agency_id
    base_scope = Maintenance.joins(:vehicle)
                             .where(vehicles: { agency_id: current_user.agency_id })
    
    # Pending maintenance - using end_date as due date
    @pending_maintenance = base_scope.where(status: 'pending')
                                      .where('maintenances.end_date >= ? OR maintenances.end_date IS NULL', Date.current)
                                      .order('maintenances.end_date ASC, maintenances.start_date ASC')
    
    # In progress maintenance
    @in_progress = base_scope.where(status: 'in_progress')
                             .order('maintenances.start_date DESC, maintenances.created_at DESC')
    
    # Recently completed - using maintenances.updated_at as completion time
    @recent_completed = base_scope.where(status: 'completed')
                                  .where('maintenances.updated_at > ?', 7.days.ago)
                                  .order('maintenances.updated_at DESC')
                                  .limit(10)
    
    # Vehicles in maintenance
    @vehicles_in_maintenance = Vehicle.where(agency_id: current_user.agency_id)
                                      .where(status: 'maintenance')
                                      .limit(10)
    
    # Overdue maintenance - end_date is in the past and status is not completed
    @overdue = base_scope.where('maintenances.end_date < ?', Date.current)
                         .where.not(status: 'completed')
                         .order('maintenances.end_date ASC')
    
    @stats = {
      pending: @pending_maintenance.count,
      in_progress: @in_progress.count,
      completed_this_week: base_scope.where(status: 'completed')
                                     .where('maintenances.updated_at > ?', 7.days.ago)
                                     .count,
      overdue: @overdue.count
    }
  end
  
  private
  
  def authorize_ptsc_maintenance!
    unless current_user.agency&.code == 'PTSC' && (current_user.maintenance_supervisor? || current_user.maintenance? || current_user.admin?)
      redirect_to root_path, alert: "Access denied. PTSC Maintenance only."
    end
  end
end