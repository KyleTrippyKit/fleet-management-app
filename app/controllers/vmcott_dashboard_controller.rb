# app/controllers/vmcott_dashboard_controller.rb
class VmcottDashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_vmcott_admin
  include AgencyStatistics
  
  def index
    @agency = current_user.agency
    
    # VMCOTT sees ALL agencies
    @all_agencies = Agency.all.order(:name)
    
    # Get data for all agencies - use the concern's methods
    @agency_stats = @all_agencies.map do |agency|
      maintenance_requests = maintenance_requests_by_status(agency)
      {
        agency: agency,
        vehicle_stats: calculate_vehicle_stats(agency),
        usage_stats: calculate_usage_stats(agency),
        maintenance_requests: maintenance_requests,
        pending_requests: maintenance_requests[:pending] || 0,
        health_score: calculate_agency_health_score(agency)
      }
    end
    
    # Overall statistics
    @overall_stats = {
      total_vehicles: Vehicle.count,
      total_agencies: Agency.count,
      total_maintenances: Maintenance.count,
      pending_requests: Maintenance.where(status: 'Pending').count,
      active_maintenances: Maintenance.where(status: 'In Progress').count,
      total_distance: Vehicle.joins(:trips).sum(:distance_km).to_f.round(1),
      total_hours: Vehicle.joins(:trips).sum(:duration_hours).to_f.round(1),
      avg_utilization: calculate_overall_utilization,
      avg_health_score: calculate_average_health_score
    }
    
    # Recent requests from all agencies
    @recent_maintenances = recent_maintenance_requests(nil, 15)
    
    # Critical alerts
    @critical_alerts = Alert.where(severity: 'critical', status: 'active')
                            .order(created_at: :desc)
                            .limit(10)
    @critical_alerts_count = @critical_alerts.count
    
    # Maintenance counts
    @overdue_maintenances_count = Maintenance.where(status: 'Pending')
                                            .where('end_date < ?', Date.today)
                                            .count
    @upcoming_maintenances_count = Maintenance.where(status: 'Pending')
                                              .where('start_date > ?', Date.today)
                                              .where('start_date <= ?', Date.today + 7.days)
                                              .count
    
    # Tell Rails to render from the vmcott folder instead of vmcott_dashboard
    render 'vmcott/index'
  end
  
  private
  
  def require_vmcott_admin
    unless current_user.admin? || current_user.role == 'super_admin'
      redirect_to root_path, alert: "Access denied. Admin privileges required."
    end
  end
  
  def calculate_overall_utilization
    total_vehicles = Vehicle.count
    active_vehicles = Vehicle.where(status: 'active').count
    total_vehicles > 0 ? ((active_vehicles.to_f / total_vehicles) * 100).round(1) : 0
  end
  
  def calculate_average_health_score
    # Placeholder - replace with actual health score calculation
    scores = Vehicle.all.map { |v| v.health_score rescue 85 }.compact
    scores.empty? ? 85 : (scores.sum / scores.size).round
  end
  
  def calculate_agency_health_score(agency)
    # Placeholder - replace with actual agency health score calculation
    vehicles = agency.vehicles
    return 85 if vehicles.empty?
    scores = vehicles.map { |v| v.health_score rescue 85 }.compact
    (scores.sum / scores.size).round
  end
end