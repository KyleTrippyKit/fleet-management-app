class AgenciesDashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :set_agency, except: [:index]
  before_action :check_agency_access, except: [:index]
  include AgencyStatistics
  
  # GET /agencies-dashboard (VMCOTT only - overview of all agencies)
  def index
    # Only VMCOTT users can access the agencies overview
    unless current_user.agency.code == "VMCOTT"
      redirect_to welcome_path, alert: "Access restricted to VMCOTT administrators."
      return
    end
    
    @agencies = Agency.subordinate_agencies.order(:name)
    @overall_stats = calculate_overall_stats
    
    # Prepare stats for each agency
    @agency_stats = @agencies.map do |agency|
      {
        agency: agency,
        vehicle_stats: calculate_vehicle_stats(agency),
        usage_stats: calculate_usage_stats(agency),
        pending_requests: Maintenance.joins(:vehicle)
                                   .where(vehicles: { agency_id: agency.id })
                                   .where(status: 'pending')
                                   .count,
        recent_vehicles: agency.vehicles.order(created_at: :desc).limit(3),
        utilization_trend: calculate_utilization_trend(agency)
      }
    end
    
    # Get recent maintenance requests from all agencies
    @recent_maintenances = Maintenance.includes(vehicle: :agency)
                                     .order(created_at: :desc)
                                     .limit(10)
  end
  
  # GET /agency-dashboard/:id (Individual agency dashboard)
  def show
    # This is accessible by agency members and VMCOTT
    @vehicle_stats = calculate_vehicle_stats(@agency)
    @usage_stats = calculate_usage_stats(@agency)
    
    @recent_vehicles = @agency.vehicles.includes(:driver, :maintenances)
                             .order(created_at: :desc)
                             .limit(5)
    
    @recent_maintenances = recent_maintenance_requests(@agency, 10)
    @vehicles_needing_attention = vehicles_needing_attention(@agency, 5)
    
    # Calculate utilization trend
    @utilization_trend = calculate_utilization_trend(@agency)
    
    # Get maintenance status distribution
    @maintenance_by_status = maintenance_requests_by_status(@agency)
  end
  
  # GET /agency-dashboard/:id/analytics
  def analytics
    @from_date = params[:from] ? Date.parse(params[:from]) : 30.days.ago.to_date
    @to_date = params[:to] ? Date.parse(params[:to]) : Date.today
    
    @vehicles = @agency.vehicles.includes(:trips, :maintenances)
    
    # Calculate vehicle analytics
    @vehicle_analytics = @vehicles.map do |vehicle|
      stats = vehicle.usage_stats(from: @from_date, to: @to_date)
      stats.merge(
        name: vehicle.display_name,
        registration_number: vehicle.registration_number,
        service_owner: vehicle.service_owner,
        health_score: vehicle.health_score,
        health_status: vehicle.health_status,
        vehicle_id: vehicle.id
      )
    end
    
    # Sort by utilization
    @vehicle_analytics = @vehicle_analytics.sort_by { |v| -(v[:utilization_percent] || 0) }
    
    # Calculate totals
    @total_distance = @vehicle_analytics.sum { |v| v[:distance_km].to_f }.round(1)
    @total_hours = @vehicle_analytics.sum { |v| v[:hours_plied].to_f }.round(1)
    @total_trips = @vehicle_analytics.sum { |v| v[:trip_count] }
    @avg_utilization = @vehicle_analytics.any? ? 
      (@vehicle_analytics.sum { |v| v[:utilization_percent].to_f } / @vehicle_analytics.size).round(1) : 0
    
    # Utilization distribution
    @high_utilization = @vehicle_analytics.count { |v| (v[:utilization_percent] || 0) >= 70 }
    @medium_utilization = @vehicle_analytics.count { |v| (v[:utilization_percent] || 0) >= 30 && (v[:utilization_percent] || 0) < 70 }
    @low_utilization = @vehicle_analytics.count { |v| (v[:utilization_percent] || 0) < 30 }
  end
  
  # GET /agency-dashboard/:id/vehicles
  def vehicles
    @query = params[:query]
    @owner_filter = params[:owner].presence && params[:owner] != "All" ? params[:owner] : nil
    
    @vehicles = @agency.vehicles.includes(:driver, :maintenances, primary_photo_attachment: { blob: :variant_records })
    
    # Apply filters
    @vehicles = @vehicles.search(@query) if @query.present?
    @vehicles = @vehicles.where(service_owner: @owner_filter) if @owner_filter.present?
    
    # For VMCOTT users viewing other agencies, add agency context
    if current_user.agency.code == "VMCOTT" && @agency.code != "VMCOTT"
      @viewing_other_agency = true
    end
    
    @vehicles = @vehicles.page(params[:page]).per(20)
  end
  
  # GET /agency-dashboard/:id/maintenance
  def maintenance
    @query = params[:query]
    @status_filter = params[:status].presence && params[:status] != "All" ? params[:status] : nil
    
    # Get maintenances for this agency
    @maintenances = Maintenance.joins(:vehicle)
                              .where(vehicles: { agency_id: @agency.id })
                              .includes(:vehicle, :service_provider)
                              .order(created_at: :desc)
    
    # Apply filters
    @maintenances = @maintenances.where(status: @status_filter) if @status_filter.present?
    @maintenances = @maintenances.where("vehicles.registration_number ILIKE ?", "%#{@query}%") if @query.present?
    
    @maintenances = @maintenances.page(params[:page]).per(20)
    
    # Maintenance statistics
    @maintenance_stats = {
      total: @maintenances.count,
      pending: @maintenances.pending.count,
      in_progress: @maintenances.where(status: 'In Progress').count,
      completed: @maintenances.completed.count,
      overdue: @maintenances.select { |m| m.overdue? }.count
    }
  end
  
  private
  
  def set_agency
    @agency = Agency.find(params[:id])
  end
  
  def check_agency_access
    # VMCOTT users can access any agency dashboard
    # Other users can only access their own agency's dashboard
    unless current_user.agency.code == "VMCOTT" || current_user.agency == @agency
      redirect_to welcome_path, alert: "You don't have access to this agency dashboard."
    end
  end
  
  def calculate_overall_stats
    agencies = Agency.where.not(code: "VMCOTT")
    
    {
      total_agencies: agencies.count,
      total_vehicles: Vehicle.count,
      total_drivers: Driver.count,
      pending_requests: Maintenance.pending.count,
      active_maintenances: Maintenance.where(status: 'In Progress').count,
      overdue_maintenances: Maintenance.overdue.count,
      total_distance: Vehicle.joins(:trips).sum(:distance_km).to_f.round(1),
      total_hours: Vehicle.joins(:trips).sum(:duration_hours).to_f.round(1),
      total_trips: Trip.count,
      avg_utilization: calculate_average_utilization(Vehicle.all)
    }
  end
  
  def calculate_utilization_trend(agency, days: 30)
    vehicles = agency.vehicles
    return [] if vehicles.empty?
    
    (0..days).map do |day_offset|
      date = Date.today - day_offset.days
      
      total_hours = vehicles.sum do |vehicle|
        vehicle.trips.where(start_time: date.beginning_of_day..date.end_of_day)
               .sum(:duration_hours).to_f
      end
      
      utilization = vehicles.count > 0 ? (total_hours / vehicles.count / 24.0 * 100).round(1) : 0
      
      {
        date: date.strftime("%b %d"),
        utilization: utilization,
        hours: total_hours.round(1)
      }
    end.reverse
  end
  
  # Helper method for calculate_average_utilization
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
end