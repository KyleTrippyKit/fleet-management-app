# app/controllers/home_controller.rb
class HomeController < ApplicationController
  skip_before_action :authenticate_user!, only: [:index]
  layout :determine_layout
  
  def index
    # Set flag to skip screensaver on home page
    @skip_screensaver = true
    
    if user_signed_in?
      redirect_to_role_dashboard
    else
      # For non-logged-in users, redirect to login page instead of blank layout
      redirect_to new_user_session_path
    end
  end

  private

  def determine_layout
    if user_signed_in?
      'application'
    else
      false
    end
  end

  def redirect_to_role_dashboard
    if current_user.nil?
      redirect_to new_user_session_path and return
    end

    Rails.logger.info "HomeController: User #{current_user.email}, Agency: #{current_user.agency&.code}, Role: #{current_user.role}"

    # ============================================
    # VMCOTT ROLE-BASED DASHBOARDS - UPDATED WITH NEW ROLE NAMES
    # ============================================
    if current_user.agency&.code == 'VMCOTT'
      case current_user.role
      when 'security_gate_officer'  # was 'receptionist'
        redirect_to vmcott_security_gate_officer_dashboard_path and return
      when 'inspector'
        redirect_to vmcott_inspector_dashboard_path and return
      when 'inventory_manager'      # was 'parts_coordinator'
        redirect_to vmcott_inventory_manager_dashboard_path and return
      when 'mechanic'
        redirect_to vmcott_mechanic_dashboard_path and return
      when 'procurement'            # was 'billing'
        redirect_to vmcott_procurement_dashboard_path and return
      when 'finance'
        redirect_to vmcott_finance_dashboard_path and return
      when 'maintenance_supervisor', 'workshop_supervisor'
        if respond_to?(:vmcott_workshop_supervisor_dashboard_path)
          redirect_to vmcott_workshop_supervisor_dashboard_path and return
        end
        redirect_to vmcott_dashboard_path and return
      when 'admin'
        redirect_to vmcott_dashboard_path and return
      else
        Rails.logger.warn "Unknown VMCOTT role: #{current_user.role}, redirecting to main dashboard"
        redirect_to vmcott_dashboard_path and return
      end
    end

    # ============================================
    # PTSC ROLE-BASED DASHBOARDS
    # ============================================
    if current_user.agency&.code == 'PTSC'
      case current_user.role
      when 'fleet_manager'
        redirect_to ptsc_fleet_dashboard_path and return
      when 'finance'
        redirect_to ptsc_finance_dashboard_path and return
      when 'driver'
        redirect_to ptsc_driver_dashboard_path and return
      when 'maintenance_supervisor', 'maintenance'
        redirect_to ptsc_maintenance_dashboard_path and return
      when 'admin'
        redirect_to ptsc_dashboard_path and return
      else
        redirect_to ptsc_dashboard_path and return
      end
    end

    # ============================================
    # OTHER AGENCY DASHBOARDS
    # ============================================
    case current_user.agency&.code
    when "TTPS"
      redirect_to (respond_to?(:ttps_dashboard_path) ? ttps_dashboard_path : main_dashboard_path) and return
    when "TTDF"
      redirect_to (respond_to?(:ttdf_dashboard_path) ? ttdf_dashboard_path : main_dashboard_path) and return
    when "FIRE"
      redirect_to (respond_to?(:fire_dashboard_path) ? fire_dashboard_path : main_dashboard_path) and return
    when "HEALTH"
      redirect_to (respond_to?(:health_dashboard_path) ? health_dashboard_path : main_dashboard_path) and return
    when "EDUCATION"
      redirect_to (respond_to?(:education_dashboard_path) ? education_dashboard_path : main_dashboard_path) and return
    end

    # ============================================
    # FALLBACK - Use role-based routing
    # ============================================
    case current_user.role
    when 'admin'
      redirect_to main_dashboard_path
    when 'fleet_manager'
      if current_user.agency.present?
        redirect_to agency_vehicles_path(current_user.agency)
      else
        redirect_to main_dashboard_path
      end
    when 'finance'
      redirect_to main_dashboard_path
    when 'driver'
      redirect_to main_dashboard_path
    when 'maintenance_supervisor', 'maintenance'
      redirect_to main_dashboard_path
    else
      redirect_to main_dashboard_path
    end
  end
end