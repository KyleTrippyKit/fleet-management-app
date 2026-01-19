# app/controllers/vmcott_dashboard_controller.rb
class VmcottDashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :verify_vmcott_agency
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
        pending_requests: maintenance_requests[:pending] || 0
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
      avg_utilization: calculate_overall_utilization
    }
    
    # Recent requests from all agencies
    @recent_maintenances = recent_maintenance_requests(nil, 15) # Use concern's method
    
    # Vehicles needing attention from all agencies
    @vehicles_needing_attention = vehicles_needing_attention(nil, 10) # Use concern's method
    
    # Or if you want to customize it, use:
    # @vehicles_needing_attention = []
    # @all_agencies.each do |agency|
    #   agency_vehicles = vehicles_needing_attention(agency, 5)
    #   agency_vehicles.each do |vehicle|
    #     @vehicles_needing_attention << {
    #       vehicle: vehicle,
    #       agency: agency,
    #       issues: get_vehicle_issues(vehicle)
    #     }
    #   end
    # end
    # @vehicles_needing_attention = @vehicles_needing_attention.first(10)
  end
  
  private
  
  def verify_vmcott_agency
    unless current_user.agency.code == "VMCOTT"
      redirect_to welcome_path, alert: "You don't have access to this dashboard"
    end
  end
  
  # Rename this method to avoid conflict with concern's method
  def calculate_overall_utilization
    # Calculate average utilization across ALL agencies
    total_vehicles = Vehicle.count
    active_vehicles = Vehicle.where(status: 'active').count
    total_vehicles > 0 ? ((active_vehicles.to_f / total_vehicles) * 100).round(1) : 0
  end
  
  # Helper method to get vehicle issues
  def get_vehicle_issues(vehicle)
    issues = []
    
    # Check fuel level
    if vehicle.fuel_level.present? && vehicle.fuel_level < 20
      issues << "Low fuel (#{vehicle.fuel_level}%)"
    end
    
    # Check for overdue maintenance
    if vehicle.maintenances.where(status: 'Pending')
                      .where('end_date < ?', Date.today)
                      .exists?
      issues << "Overdue maintenance"
    end
    
    # Check if vehicle has active alerts
    if vehicle.alerts.where(status: 'active').exists?
      issues << "Active alerts"
    end
    
    issues
  end
end