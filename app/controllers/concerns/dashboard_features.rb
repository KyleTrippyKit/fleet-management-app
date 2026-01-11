# app/controllers/concerns/dashboard_features.rb
module DashboardFeatures
  extend ActiveSupport::Concern
  
  def vehicle_usage_analytics(agency = nil)
    vehicles = agency ? agency.vehicles : Vehicle.all
    
    {
      total_distance: vehicles.joins(:trips).sum(:distance_km),
      average_utilization: calculate_average_utilization(vehicles),
      fuel_consumption: calculate_fuel_consumption(vehicles),
      maintenance_cost: calculate_maintenance_cost(vehicles)
    }
  end
  
  def maintenance_requests(agency = nil)
    requests = agency ? Maintenance.joins(:vehicle).where(vehicles: { agency_id: agency.id }) : Maintenance.all
    
    requests.group_by(&:status).transform_values(&:count)
  end
  
  def upcoming_maintenances(agency = nil)
    vehicles = agency ? agency.vehicles : Vehicle.all
    
    vehicles.joins(:maintenances)
            .where(maintenances: { status: ['scheduled', 'pending'] })
            .order('maintenances.scheduled_date ASC')
            .limit(20)
  end
end