# app/controllers/ptsc/driver_dashboard_controller.rb
class Ptsc::DriverDashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_ptsc_driver!
  
  def index
    # Get assigned vehicle directly from the database
    @assigned_vehicle = Vehicle.find_by(driver_id: current_user.id)
    
    # Get trips for this driver
    @my_trips = Trip.where(driver_id: current_user.id)
                    .order(start_time: :desc)
                    .limit(10)
    
    # Upcoming trips (future start times)
    @upcoming_trips = Trip.where(driver_id: current_user.id)
                          .where('start_time > ?', Time.current)
                          .order(start_time: :asc)
                          .limit(5)
    
    # Recent alerts
    @recent_alerts = Alert.where(driver_id: current_user.id)
                          .order(created_at: :desc)
                          .limit(5)
    
    # Calculate stats - Remove status reference, calculate completed based on end_time
    all_trips = Trip.where(driver_id: current_user.id)
    
    @stats = {
      total_trips: all_trips.count,
      total_distance: all_trips.sum(:distance_km),
      completed_trips: all_trips.where.not(end_time: nil).count, # Trips with an end time are completed
      pending_alerts: Alert.where(driver_id: current_user.id, status: 'active').count
    }
    
    # Log for debugging (optional)
    Rails.logger.debug "Ptsc::DriverDashboard#index - User: #{current_user.email}, Vehicle: #{@assigned_vehicle&.license_plate}"
  end
  
  private
  
  def authorize_ptsc_driver!
    unless current_user.agency&.code == 'PTSC' && (current_user.driver? || current_user.admin?)
      redirect_to root_path, alert: "Access denied. PTSC Drivers only."
    end
  end
end