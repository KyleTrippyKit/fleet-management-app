# app/controllers/ptsc/fleet_dashboard_controller.rb
class Ptsc::FleetDashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_ptsc_fleet!
  
  def index
    @vehicles = Vehicle.where(agency_id: current_user.agency_id)
    @active_alerts = Alert.where(agency_id: current_user.agency_id, status: 'active')
    
    # Get maintenance through vehicles instead of directly by agency_id
    @maintenance_schedule = Maintenance.joins(:vehicle)
                                       .where(vehicles: { agency_id: current_user.agency_id })
                                       .upcoming
                                       .limit(10)
    
    @stats = {
      total_vehicles: @vehicles.count,
      active_vehicles: @vehicles.where(status: 'active').count,
      maintenance_vehicles: @vehicles.where(status: 'maintenance').count,
      active_alerts: @active_alerts.count
    }
  end
  
  private
  
  def authorize_ptsc_fleet!
    unless current_user.agency&.code == 'PTSC' && (current_user.fleet_manager? || current_user.admin?)
      redirect_to root_path, alert: "Access denied. PTSC Fleet Managers only."
    end
  end
end