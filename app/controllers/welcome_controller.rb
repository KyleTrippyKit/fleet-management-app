# frozen_string_literal: true

class WelcomeController < ApplicationController
  # Authentication and agency setup
  before_action :authenticate_user!
  before_action :verify_agency_assigned, except: [:no_agency_assigned, :debug_agency]
  before_action :set_agency, except: [:no_agency_assigned]

  # ============================================
  # Public Actions
  # ============================================

  # Main welcome portal after login
  def index
    log_welcome_access

    # ✅ Scanner/Inspector users should ALWAYS go to their home screens
    if current_user&.scanner_role?
      redirect_to scanner_home_path
      return
    end

    # If user has a specific agency dashboard, redirect there
    if current_user&.inspector_role?
      redirect_to inspector_home_path
      return
    end

    # Otherwise, render the generic welcome page
    render :index
  end

  # Scanner interface page (optional if you use /home as the scanner screen)
  def scan
    # Simple scanner page - agency context already set
  end

  # Logout confirmation page
  def logout
    # Simple logout confirmation page
  end

  # Dashboard redirector - routes to appropriate agency dashboard
  def dashboard
    log_dashboard_redirect

     # ✅ Scanner/Inspector users should NEVER be routed to dashboards
    if current_user&.scanner_role?
      redirect_to scanner_home_path
      return
    end

    if current_user&.inspector_role?
      redirect_to inspector_home_path
      return
    end

    if @agency.present?
      redirect_to agency_dashboard_path
    else
      redirect_to main_dashboard_path
    end
  end


  # Page for users without agency assignment
  def no_agency_assigned
    # Don't set @agency for this page
    flash.now[:alert] = "Your account is not assigned to an agency." if current_user.agency.nil?
  end

  # ============================================
  # Debug/Development Actions
  # ============================================

  # Debug page to inspect agency information
  def debug_agency
    @agency = current_user.agency

    render plain: <<~DEBUG
      === AGENCY DEBUG INFORMATION ===

      User Information:
      - Email: #{current_user.email}
      - User ID: #{current_user.id}
      - Agency ID: #{current_user.agency_id}

      Agency Information:
      - Agency Object: #{@agency.inspect}
      - Agency Code: '#{@agency&.code}'
      - Agency Name: '#{@agency&.name}'

      Database Verification:
      - User's agency_id from DB: #{User.where(email: current_user.email).pluck(:agency_id).inspect}

      All Available Agencies:
      #{Agency.all.map { |a| "#{a.id}: #{a.code} (#{a.name})" }.join("\n      ")}

      Agency Code Matching:
      - 'VMCOTT': #{@agency&.code == "VMCOTT"}
      - 'TTPS': #{@agency&.code == "TTPS"}
      - 'TTDF': #{@agency&.code == "TTDF"}
      - 'PTSC': #{@agency&.code == "PTSC"}
      - Any other: #{@agency&.code.present? && !["VMCOTT", "TTPS", "TTDF", "PTSC"].include?(@agency&.code)}

      Dashboard Routing:
      - Will redirect to: #{agency_dashboard_path}
      - Should redirect: #{should_redirect_to_agency_dashboard?}

      Scanner Routing:
      - Is scanner user?: #{current_user&.scanner_role?}
      - Scanner home path: #{scanner_home_path}

      === END DEBUG ===
    DEBUG
  end

  # ============================================
  # Private Methods
  # ============================================
  private

  # Verify user has an agency assigned
  def verify_agency_assigned
    Rails.logger.info "=== VERIFY AGENCY ASSIGNED ==="
    Rails.logger.info "Current user: #{current_user&.email}"
    Rails.logger.info "Current user agency: #{current_user&.agency&.inspect}"
    Rails.logger.info "Current user agency_id: #{current_user&.agency_id}"

    return if current_user.agency.present?

    Rails.logger.info "=== NO AGENCY - REDIRECTING ==="
    session[:return_to] = request.fullpath if request.get?
    redirect_to no_agency_assigned_path,
                alert: "Your account is not assigned to an agency. Please contact an administrator."
  end

  # Set agency for the current request
  def set_agency
    @agency = current_user.agency
  end

  # Check if user should be redirected to a specific agency dashboard
  def should_redirect_to_agency_dashboard?
    return false if current_user&.scanner_role? || current_user&.inspector_role?
    @agency.present? && agency_has_specific_dashboard?(@agency.code)
  end

  # Check if agency has a specific dashboard
  def agency_has_specific_dashboard?(agency_code)
    ["VMCOTT", "TTPS", "TTDF", "PTSC"].include?(agency_code)
  end

  # Determine the correct dashboard path
  def agency_dashboard_path
    case @agency&.code
    when "VMCOTT" then vmcott_dashboard_path
    when "TTPS"   then ttps_dashboard_path
    when "TTDF"   then ttdf_dashboard_path
    when "PTSC"   then ptsc_dashboard_path
    else               main_dashboard_path
    end
  end

  # Log welcome page access
  def log_welcome_access
    Rails.logger.info "[WelcomeController] User #{current_user.email} accessed welcome page"
    Rails.logger.info "[WelcomeController] Agency: #{@agency&.code} (ID: #{@agency&.id})"
    Rails.logger.info "[WelcomeController] Redirect to agency dashboard: #{should_redirect_to_agency_dashboard?}"
  end

  # Log dashboard redirect
  def log_dashboard_redirect
    Rails.logger.info "[WelcomeController] Dashboard redirect for user #{current_user.email}"
    Rails.logger.info "[WelcomeController] Agency code: '#{@agency&.code}'"
    Rails.logger.info "[WelcomeController] Redirecting to: #{agency_dashboard_path}"
  end
end
