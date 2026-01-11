# app/controllers/main_dashboard_controller.rb
class MainDashboardController < ApplicationController
  before_action :authenticate_user!
  
  def index
    # ========================
    # ALERT STATISTICS
    # ========================
    @active_alerts_count = Alert.active_count
    @critical_alerts_count = Alert.critical_count
    @urgent_alerts_count = Alert.urgent_count
    @needs_attention_count = Alert.needs_attention_count
    
    # ========================
    # ALERTS NEEDING IMMEDIATE ATTENTION
    # ========================
    @alerts_needing_attention = Alert.needs_attention.includes(:vehicle, :driver).limit(10)
    
    # ========================
    # VEHICLE STATISTICS WITH ALERTS
    # ========================
    @vehicles = load_vehicles_for_user
    
    # ========================
    # VEHICLES WITH ALERT SUMMARIES
    # ========================
    @vehicles_with_stats = @vehicles.map do |vehicle|
      {
        vehicle: vehicle,
        alert_summary: vehicle.alert_summary,
        health_score: vehicle.comprehensive_health_score,
        needs_attention: vehicle.needs_immediate_attention?
      }
    end
    
    # Sort vehicles by those needing attention first
    @vehicles_with_stats.sort_by! do |vehicle_data|
      vehicle_data[:needs_attention] ? 0 : 1
    end
    
    # Limit to top 10 for dashboard
    @vehicles_with_stats = @vehicles_with_stats.take(10)
    
    # ========================
    # OVERALL FLEET STATISTICS
    # ========================
    @total_vehicles = @vehicles.count
    @active_vehicles = @vehicles.count { |v| v.status == 'active' }
    @maintenance_vehicles = @vehicles.count { |v| v.status == 'maintenance' }
    @overdue_vehicles = @vehicles.count { |v| v.status == 'overdue' }
    
    # ========================
    # MAINTENANCE STATISTICS
    # ========================
    @total_maintenances = Maintenance.count
    @pending_maintenances = Maintenance.pending.count
    @overdue_maintenances = Maintenance.overdue.count
    @active_maintenances = Maintenance.active.count
    
    # ========================
    # UTILIZATION STATISTICS
    # ========================
    if @vehicles.any?
      total_utilization = @vehicles.sum { |v| v.calculate_utilization }
      @avg_utilization = (total_utilization / @vehicles.count).round(1)
    else
      @avg_utilization = 0
    end
    
    # ========================
    # RECENT ACTIVITY
    # ========================
    @recent_trips = Trip.order(start_time: :desc).limit(5).includes(:vehicle, :driver)
    @recent_maintenances = Maintenance.order(date: :desc).limit(5).includes(:vehicle)
    @recent_alerts = Alert.recent.limit(5).includes(:vehicle)
    
    # ========================
    # HEALTH DISTRIBUTION
    # ========================
    @health_distribution = {
      excellent: @vehicles.count { |v| v.health_status == 'excellent' },
      good: @vehicles.count { |v| v.health_status == 'good' },
      fair: @vehicles.count { |v| v.health_status == 'fair' },
      poor: @vehicles.count { |v| v.health_status == 'poor' },
      critical: @vehicles.count { |v| v.health_status == 'critical' }
    }
  end
  
  # Quick actions for dashboard
  def acknowledge_alert
    @alert = Alert.find(params[:id])
    if @alert.acknowledge!(current_user)
      redirect_to main_dashboard_path, notice: "Alert acknowledged successfully."
    else
      redirect_to main_dashboard_path, alert: "Failed to acknowledge alert."
    end
  end
  
  def resolve_alert
    @alert = Alert.find(params[:id])
    if @alert.resolve!(params[:resolution_notes])
      redirect_to main_dashboard_path, notice: "Alert resolved successfully."
    else
      redirect_to main_dashboard_path, alert: "Failed to resolve alert."
    end
  end
  
  private
  
  def load_vehicles_for_user
    # Check if user has vmcott? method, otherwise check admin role
    if current_user.respond_to?(:vmcott?) && current_user.vmcott?
      # VMCOTT users see all vehicles
      Vehicle.all.includes(:agency, :driver, :alerts)
    elsif current_user.admin?
      # Admin users see all vehicles
      Vehicle.all.includes(:agency, :driver, :alerts)
    elsif current_user.agency.present?
      # Other users see only their agency's vehicles
      current_user.agency.vehicles.includes(:driver, :alerts)
    else
      # No agency assigned - show empty
      Vehicle.none
    end
  end
end