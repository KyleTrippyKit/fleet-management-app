# app/controllers/vmcott_dashboard_controller.rb
class VmcottDashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :verify_vmcott_agency
  include AgencyStatistics
  
  def index
    @agency = current_user.agency
    
    # VMCOTT sees ALL agencies
    @all_agencies = Agency.all.order(:name)
    
    # Get data for all agencies
    @agency_stats = @all_agencies.map do |agency|
      {
        agency: agency,
        vehicle_stats: calculate_vehicle_stats(agency),
        usage_stats: calculate_usage_stats(agency),
        maintenance_requests: maintenance_requests_by_status(agency)
      }
    end
    
    # Overall statistics
    @overall_stats = {
      total_vehicles: Vehicle.count,
      total_agencies: Agency.count,
      total_maintenances: Maintenance.count,
      pending_maintenances: Maintenance.where(status: 'pending').count,
      active_maintenances: Maintenance.where(status: 'in_progress').count,
      total_distance: Vehicle.joins(:trips).sum(:distance_km).to_f.round(1),
      total_hours: Vehicle.joins(:trips).sum(:duration_hours).to_f.round(1)
    }
    
    # Recent requests from all agencies
    @recent_requests = Maintenance.includes(vehicle: :agency)
                                 .order(created_at: :desc)
                                 .limit(15)
    
    # Vehicles needing attention from all agencies
    @vehicles_needing_attention = []
    @all_agencies.each do |agency|
      agency.vehicles.each do |vehicle|
        if vehicle.needs_immediate_attention?
          @vehicles_needing_attention << {
            vehicle: vehicle,
            agency: agency,
            issues: []
          }
        end
      end
    end
    @vehicles_needing_attention = @vehicles_needing_attention.first(10)
  end
  
  private
  
  def verify_vmcott_agency
    unless current_user.agency.code == "VMCOTT"
      redirect_to welcome_path, alert: "You don't have access to this dashboard"
    end
  end
end