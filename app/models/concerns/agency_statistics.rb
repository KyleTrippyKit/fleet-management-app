# app/models/concerns/agency_statistics.rb
module AgencyStatistics
  extend ActiveSupport::Concern
  
  included do
    # Optional: Add any associations or validations here if needed
  end
  
  # Calculate vehicle statistics for an agency
  def agency_vehicle_stats(agency = nil)
    vehicles = agency ? agency.vehicles : Vehicle.all
    
    total_vehicles = vehicles.count
    active_vehicles = vehicles.where(status: 'active').count
    
    # Get vehicle IDs for maintenance queries
    vehicle_ids = vehicles.pluck(:id)
    
    # Maintenance status counts
    pending_maintenances = vehicles.joins(:maintenances)
                                  .where(maintenances: { status: 'pending' })
                                  .distinct
                                  .count
                                  
    active_maintenances = vehicles.joins(:maintenances)
                                 .where(maintenances: { status: 'In Progress' })
                                 .distinct
                                 .count
    
    # Vehicles with overdue maintenance
    overdue_maintenances = Maintenance.where(vehicle_id: vehicle_ids)
                                     .where('next_due_date < ?', Date.today)
                                     .where(status: ['pending', 'scheduled'])
                                     .count
    
    {
      total_vehicles: total_vehicles,
      active_vehicles: active_vehicles,
      inactive_vehicles: vehicles.where(status: 'inactive').count,
      pending_maintenances: pending_maintenances,
      scheduled_maintenances: vehicles.joins(:maintenances).where(maintenances: { status: 'scheduled' }).distinct.count,
      completed_maintenances: vehicles.joins(:maintenances).where(maintenances: { status: 'completed' }).distinct.count,
      active_maintenances: active_maintenances,
      overdue_maintenances: overdue_maintenances,
      available_vehicles: total_vehicles - (pending_maintenances + active_maintenances)
    }
  end
  
  # Calculate usage statistics for an agency
  def agency_usage_stats(agency = nil)
    vehicles = agency ? agency.vehicles : Vehicle.all
    
    total_distance = vehicles.joins(:trips).sum(:distance_km).to_f
    total_hours = vehicles.joins(:trips).sum(:duration_hours).to_f
    total_trips = vehicles.joins(:trips).count
    
    # Calculate from last 30 days for additional metrics
    from_date = 30.days.ago.to_date
    to_date = Date.today
    
    # Alternative calculation using vehicle.usage_stats if available
    if vehicles.first&.respond_to?(:usage_stats)
      calculated_stats = calculate_usage_stats_from_vehicles(vehicles, from_date, to_date)
    else
      calculated_stats = {}
    end
    
    {
      total_distance: total_distance.round(1),
      total_hours: total_hours.round(1),
      total_trips: total_trips,
      average_utilization: calculate_average_utilization(vehicles),
      fuel_cost: calculate_fuel_cost(vehicles),
      fuel_consumption: calculated_stats[:fuel_consumption] || calculate_estimated_fuel_consumption(vehicles),
      maintenance_cost: calculate_maintenance_cost(vehicles),
      last_30_days: calculated_stats # Include detailed 30-day stats if available
    }.compact
  end
  
  # Get recent maintenance requests
  def recent_maintenance_requests(agency = nil, limit = 10)
    maintenances = agency ? 
      Maintenance.joins(:vehicle).where(vehicles: { agency_id: agency.id }) : 
      Maintenance.all
    
    maintenances.includes(:vehicle, :service_provider)
               .order(created_at: :desc)
               .limit(limit)
  end
  
  # Get maintenance requests by status
  def maintenance_requests_by_status(agency = nil)
    maintenances = agency ? 
      Maintenance.joins(:vehicle).where(vehicles: { agency_id: agency.id }) : 
      Maintenance.all
    
    maintenances.group(:status).count
  end
  
  # Get vehicles needing attention (overdue maintenance, low fuel, etc.)
  def vehicles_needing_attention(agency = nil, limit = 10)
    vehicles = agency ? 
      agency.vehicles.includes(:maintenances) : 
      Vehicle.all.includes(:maintenances)
    
    vehicles.select do |vehicle|
      vehicle.maintenance_overdue? || 
      (vehicle.respond_to?(:fuel_level) && vehicle.fuel_level.present? && vehicle.fuel_level < 20) ||
      (vehicle.respond_to?(:health_status) && vehicle.health_status == 'critical') ||
      (vehicle.respond_to?(:insurance_expired?) && vehicle.insurance_expired?)
    end.first(limit)
  end
  
  private
  
  def calculate_average_utilization(vehicles)
    return 0 if vehicles.empty?
    
    # Try to use vehicle-specific utilization calculation if available
    if vehicles.first.respond_to?(:utilization_percent)
      total_utilization = vehicles.sum { |v| v.utilization_percent.to_f }
      return (total_utilization / vehicles.count).round(1)
    end
    
    # Fallback calculation based on trip hours
    total_hours = vehicles.joins(:trips).sum(:duration_hours).to_f
    total_days = 30 # Default to 30-day period
    total_possible_hours = vehicles.count * 24 * total_days
    
    return 0 if total_possible_hours <= 0
    
    utilization_percent = (total_hours / total_possible_hours * 100).round(1)
    utilization_percent
  end
  
  def calculate_fuel_cost(vehicles)
    # Simplified calculation - adjust based on your business logic
    total_distance = vehicles.joins(:trips).sum(:distance_km).to_f
    (total_distance / 12.0 * 4.5).round(2) # 12 km/L at $4.5/L
  end
  
  def calculate_estimated_fuel_consumption(vehicles)
    total_distance = vehicles.joins(:trips).sum(:distance_km).to_f
    (total_distance / 12.0).round(2) # 12 km/L average
  end
  
  def calculate_maintenance_cost(vehicles)
    Maintenance.where(vehicle_id: vehicles.pluck(:id)).sum(:cost).to_f.round(2)
  end
  
  # Helper method to calculate usage stats from vehicle-specific method
  def calculate_usage_stats_from_vehicles(vehicles, from_date, to_date)
    total_distance = 0
    total_hours = 0
    total_trips = 0
    
    vehicles.each do |vehicle|
      stats = vehicle.usage_stats(from: from_date, to: to_date)
      total_distance += stats[:distance_km].to_f
      total_hours += stats[:hours_plied].to_f
      total_trips += stats[:trip_count]
    end
    
    # Calculate average utilization
    avg_utilization = calculate_detailed_average_utilization(vehicles, from_date, to_date)
    
    # Calculate fuel consumption (simplified)
    fuel_consumption = (total_distance / 12.0 * 4.5).round(2) # 12 km/L at $4.5/L
    
    {
      distance_km: total_distance.round(1),
      hours_plied: total_hours.round(1),
      trip_count: total_trips,
      utilization_percent: avg_utilization,
      fuel_consumption_cost: fuel_consumption
    }
  end
  
  def calculate_detailed_average_utilization(vehicles, from_date, to_date)
    return 0 if vehicles.empty?
    
    total_days = (to_date - from_date + 1).to_i
    return 0 if total_days <= 0
    
    total_utilization = vehicles.sum do |vehicle|
      stats = vehicle.usage_stats(from: from_date, to: to_date)
      stats[:utilization_percent].to_f
    end
    
    (total_utilization / vehicles.count).round(1)
  end
  
  # Alias methods for compatibility with old naming
  def calculate_vehicle_stats(agency = nil)
    agency_vehicle_stats(agency)
  end
  
  def calculate_usage_stats(agency = nil)
    agency_usage_stats(agency)
  end
end