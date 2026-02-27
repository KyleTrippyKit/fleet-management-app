# app/controllers/home_controller.rb
class HomeController < ApplicationController
  skip_before_action :authenticate_user!, only: [:index]
  
  def index
    if user_signed_in?
      redirect_to_role_dashboard
    else
      redirect_to new_user_session_path
    end
  end

  private

  def redirect_to_role_dashboard
    if current_user.nil?
      redirect_to new_user_session_path and return
    end

    # Log for debugging (you can remove this after confirming it works)
    Rails.logger.info "HomeController: User #{current_user.email}, Agency: #{current_user.agency&.code}, Role: #{current_user.role}"

    # PTSC Admin goes to PTSC dashboard
    if current_user.agency&.code == 'PTSC' && current_user.admin?
      redirect_to ptsc_dashboard_path and return
    end

    # PTSC users by role
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
      else
        redirect_to ptsc_dashboard_path and return
      end
    end

    # VMCOTT users (including admins) always go to VMCOTT dashboard
    if current_user.agency&.code == 'VMCOTT'
      redirect_to vmcott_dashboard_path and return
    end

    # For other agencies, use role-based routing
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
      # Legacy agency-based dashboards as fallback
      case current_user.agency&.code
      when "TTPS"   then ttps_dashboard_path
      when "TTDF"   then ttdf_dashboard_path
      else
        main_dashboard_path
      end
    end
  end
end