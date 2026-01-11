module AgencyStatistics
  extend ActiveSupport::Concern
  
  included do
    helper_method :agency_scope, :is_vmcott?
  end
  
  private
  
  # Check if user is VMCOTT (central authority)
  def is_vmcott?
    current_user.agency.code == "VMCOTT"
  end
  
  # Get the appropriate scope for the current user
  def agency_scope
    if is_vmcott?
      # VMCOTT sees everything
      nil
    else
      # Other agencies only see their own data
      current_user.agency
    end
  end
  
  # Get vehicles for current user's agency scope
  def scoped_vehicles
    if is_vmcott?
      Vehicle.all.includes(:agency)
    else
      current_user.agency.vehicles
    end
  end
  
  # Get maintenances for current user's agency scope
  def scoped_maintenances
    if is_vmcott?
      Maintenance.all.includes(vehicle: :agency)
    else
      Maintenance.joins(:vehicle).where(vehicles: { agency_id: current_user.agency.id })
    end
  end
  
  # Calculate vehicle statistics for an agency
  def calculate_vehicle_stats(agency = nil)
    vehicles = agency ? agency.vehicles : scoped_vehicles
    
    total_vehicles = vehicles.count
    active_vehicles = vehicles.where(status: 'active').count
    
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
    overdue_maintenances = vehicles.joins(:maintenances)
                                 .where('maintenances.next_due_date < ?', Date.today)
                                 .where(maintenances: { status: ['pending', 'scheduled'] })
                                 .distinct
                                 .count
    
    {
      total_vehicles: total_vehicles,
      active_vehicles: active_vehicles,
      pending_maintenances: pending_maintenances,
      active_maintenances: active_maintenances,
      overdue_maintenances: overdue_maintenances,
      available_vehicles: total_vehicles - (pending_maintenances + active_maintenances)
    }
  end
  
  # Calculate usage statistics for an agency
  def calculate_usage_stats(agency = nil)
    vehicles = agency ? agency.vehicles : scoped_vehicles
    
    # Calculate from last 30 days
    from_date = 30.days.ago.to_date
    to_date = Date.today
    
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
    avg_utilization = calculate_average_utilization(vehicles, from_date, to_date)
    
    # Calculate fuel consumption (simplified)
    fuel_consumption = (total_distance / 12.0 * 4.5).round(2) # 12 km/L at $4.5/L
    
    # Calculate maintenance cost
    maintenance_cost = calculate_maintenance_cost(agency)
    
    {
      total_distance: total_distance.round(1),
      total_hours: total_hours.round(1),
      total_trips: total_trips,
      average_utilization: avg_utilization,
      fuel_consumption: fuel_consumption,
      maintenance_cost: maintenance_cost
    }
  end
  
  # Calculate average vehicle utilization
  def calculate_average_utilization(vehicles, from_date = 30.days.ago.to_date, to_date = Date.today)
    return 0 if vehicles.empty?
    
    total_days = (to_date - from_date + 1).to_i
    return 0 if total_days <= 0
    
    total_utilization = vehicles.sum do |vehicle|
      stats = vehicle.usage_stats(from: from_date, to: to_date)
      stats[:utilization_percent].to_f
    end
    
    (total_utilization / vehicles.count).round(1)
  end
  
  # Calculate maintenance cost for an agency
  def calculate_maintenance_cost(agency = nil)
    maintenances = agency ? 
      Maintenance.joins(:vehicle).where(vehicles: { agency_id: agency.id }) : 
      scoped_maintenances
    
    maintenances.sum(:cost).to_f.round(2)
  end
  
  # Get recent maintenance requests
  def recent_maintenance_requests(agency = nil, limit = 10)
    maintenances = agency ? 
      Maintenance.joins(:vehicle).where(vehicles: { agency_id: agency.id }) : 
      scoped_maintenances
    
    maintenances.includes(:vehicle, :service_provider)
               .order(created_at: :desc)
               .limit(limit)
  end
  
  # Get maintenance requests by status
  def maintenance_requests_by_status(agency = nil)
    maintenances = agency ? 
      Maintenance.joins(:vehicle).where(vehicles: { agency_id: agency.id }) : 
      scoped_maintenances
    
    maintenances.group(:status).count
  end
  
  # Get vehicles needing attention (overdue maintenance, low fuel, etc.)
  def vehicles_needing_attention(agency = nil, limit = 10)
    vehicles = agency ? agency.vehicles.includes(:maintenances) : scoped_vehicles.includes(:maintenances)
    
    vehicles.select do |vehicle|
      vehicle.maintenance_overdue? || 
      (vehicle.fuel_level.present? && vehicle.fuel_level < 20) ||
      vehicle.health_status == 'critical' ||
      (vehicle.respond_to?(:insurance_expired?) && vehicle.insurance_expired?)
    end.first(limit)
  end
  
  # Alias methods for compatibility
  def agency_vehicle_stats(agency = nil)
    calculate_vehicle_stats(agency)
  end
  
  def agency_usage_stats(agency = nil)
    calculate_usage_stats(agency)
  end
end