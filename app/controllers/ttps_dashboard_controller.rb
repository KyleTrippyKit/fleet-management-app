# app/controllers/ttps_dashboard_controller.rb
class TtpsDashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :verify_ttps_agency
  include AgencyStatistics
  
  def index
    @agency = current_user.agency
    
    # Agency-specific statistics
    @vehicle_stats = calculate_vehicle_stats(@agency)
    @usage_stats = calculate_usage_stats(@agency)
    @maintenance_requests = maintenance_requests_by_status(@agency)
    
    # Recent vehicles and maintenances
    @recent_vehicles = @agency.vehicles.order(created_at: :desc).limit(5)
    @recent_maintenances = recent_maintenance_requests(@agency, 10)
    @vehicles_needing_attention = vehicles_needing_attention(@agency, 5)
    
    # Quick stats for dashboard cards
    @quick_stats = {
      active_vehicles_count: @agency.vehicles.where(status: 'active').count,
      pending_requests: Maintenance.joins(:vehicle)
                                  .where(vehicles: { agency_id: @agency.id })
                                  .where(status: 'pending')
                                  .count,
      overdue_maintenances: Maintenance.joins(:vehicle)
                                      .where(vehicles: { agency_id: @agency.id })
                                      .where("maintenances.end_date < ?", Date.today)
                                      .count,
      total_cost: Maintenance.joins(:vehicle)
                            .where(vehicles: { agency_id: @agency.id })
                            .sum(:cost).to_f.round(2)
    }
    
    # Vehicles with high utilization
    @high_utilization_vehicles = @agency.vehicles.select do |vehicle|
      vehicle.calculate_utilization >= 70
    end.first(5)
  end
  
  private
  
  def verify_ttps_agency
    unless current_user.agency.code == "TTPS"
      redirect_to welcome_path, alert: "You don't have access to this dashboard"
    end
  end
end