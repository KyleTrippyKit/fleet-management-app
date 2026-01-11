# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  # Remove Pundit::Authorization
  
  # Only allow modern browsers supporting essential features
  allow_browser versions: :modern
  
  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # IMPORTANT: CSRF protection configuration
  protect_from_forgery with: :exception, prepend: true
  
  # Devise controllers handle their own CSRF protection
  skip_before_action :verify_authenticity_token, if: :devise_controller?

  # =====================================================
  # Callbacks
  # =====================================================
  before_action :set_current_user
  before_action :set_timezone
  before_action :check_for_turbo_frame
  before_action :set_agency_theme

  # =====================================================
  # AFTER SIGN IN REDIRECT - THE FIX!
  # =====================================================
  def after_sign_in_path_for(resource)
    # Debug logging
    Rails.logger.info "=== AFTER SIGN IN REDIRECT ==="
    Rails.logger.info "User: #{resource.email}"
    Rails.logger.info "Agency Code: #{resource.agency&.code}"
    Rails.logger.info "Role: #{resource.role}"
    Rails.logger.info "=============================="
    
    # Redirect PTSC users to their specialized dashboard
    if resource.agency&.code == 'PTSC'
      ptsc_dashboard_path
    # Add other agency-specific dashboards here as needed
    elsif resource.agency&.code == 'VMCOTT'
      vmcott_dashboard_path
    elsif resource.agency&.code == 'TTPS'
      ttps_dashboard_path
    elsif resource.agency&.code == 'TTDF'
      ttdf_dashboard_path
    else
      # Default to main dashboard
      main_dashboard_path
    end
  end

  # =====================================================
  # Helper Methods (KEEP THESE!)
  # =====================================================
  helper_method :current_agency, 
                :admin?, 
                :manager?, 
                :vmcott?,
                :current_user_role,
                :owner_color,
                :urgency_badge_class,
                :status_badge_class,
                :format_date,
                :format_currency

  # =====================================================
  # Public Methods
  # =====================================================

  # Get current agency/organization
  def current_agency
    @current_agency ||= current_user&.agency
  end

  # Check if user is an admin
  def admin?
    return false unless current_user
    current_user.admin? || current_user.role == 'admin'
  end

  # Check if user is a manager
  def manager?
    return false unless current_user
    current_user.manager? || current_user.role == 'manager' || admin?
  end

  # Check if user belongs to VMCOTT agency
  def vmcott?
    current_agency&.code == 'VMCOTT'
  end
  alias_method :is_vmcott?, :vmcott?

  # Get current user role
  def current_user_role
    current_user&.role || 'guest'
  end

  # Color coding for service owners
  def owner_color(owner)
    case owner.to_s.downcase
    when 'ptsc'         then 'primary'
    when 'police'       then 'danger'
    when 'fire service', 'fire' then 'warning'
    when 'ambulance', 'medical' then 'info'
    when 'government'   then 'secondary'
    else 'dark'
    end
  end

  # Badge class for maintenance urgency
  def urgency_badge_class(urgency)
    case urgency.to_s.downcase
    when 'emergency'  then 'bg-danger text-white'
    when 'scheduled'  then 'bg-warning text-dark'
    when 'routine'    then 'bg-primary text-white'
    else 'bg-secondary text-white'
    end
  end

  # Badge class for maintenance status
  def status_badge_class(status)
    case status.to_s.downcase
    when 'completed' then 'bg-success text-white'
    when 'pending'   then 'bg-warning text-dark'
    when 'cancelled' then 'bg-secondary text-white'
    else 'bg-info text-white'
    end
  end

  # Format date consistently
  def format_date(date, format: :medium)
    return "N/A" if date.blank?
    
    case format
    when :short
      date.strftime("%Y-%m-%d")
    when :medium
      date.strftime("%b %d, %Y")
    when :long
      date.strftime("%B %d, %Y")
    when :with_time
      date.strftime("%Y-%m-%d %H:%M")
    else
      date.strftime("%Y-%m-%d")
    end
  end

  # Format currency
  def format_currency(amount, currency: "TTD")
    return "N/A" if amount.blank?
    number_to_currency(amount, unit: "$", separator: ".", delimiter: ",")
  end

  # =====================================================
  # Pagination
  # =====================================================
  def per_page
    params[:per_page] || 20
  end
  helper_method :per_page

  # =====================================================
  # JSON Response Helpers
  # =====================================================
  def render_json_success(data = {}, message = nil)
    render json: {
      success: true,
      message: message,
      data: data
    }
  end

  def render_json_error(message = "An error occurred", errors = {}, status: :unprocessable_entity)
    render json: {
      success: false,
      message: message,
      errors: errors
    }, status: status
  end

  # =====================================================
  # Authorization Shortcuts (KEEP THESE!)
  # =====================================================
  
  # Authorize admin access
  def authorize_admin!
    return if admin?
    flash[:alert] = "You are not authorized to perform this action."
    redirect_back(fallback_location: root_path)
  end

  # Authorize manager access
  def authorize_manager!
    return if manager?
    flash[:alert] = "You are not authorized to perform this action."
    redirect_back(fallback_location: root_path)
  end

  # Authorize fleet manager access
  def authorize_fleet_manager!
    return if current_user&.fleet_manager? || manager?
    flash[:alert] = "You must be a fleet manager to perform this action."
    redirect_back(fallback_location: root_path)
  end

  # Authorize maintenance supervisor access
  def authorize_maintenance_supervisor!
    return if current_user&.maintenance_supervisor? || manager?
    flash[:alert] = "You must be a maintenance supervisor to perform this action."
    redirect_back(fallback_location: root_path)
  end

  # Authorize finance access
  def authorize_finance!
    return if current_user&.finance? || manager?
    flash[:alert] = "You must have finance access to perform this action."
    redirect_back(fallback_location: root_path)
  end

  # Check if user can manage a specific resource
  def authorize_owner!(resource)
    return if admin?
    return if resource.user_id == current_user.id
    return if resource.respond_to?(:created_by) && resource.created_by == current_user.id
    
    flash[:alert] = "You are not authorized to manage this resource."
    redirect_back(fallback_location: root_path)
  end

  # Check if user can view a specific resource
  def authorize_viewer!(resource)
    return if admin? || manager?
    
    if resource.respond_to?(:user_id) && resource.user_id != current_user.id
      flash[:alert] = "You are not authorized to view this resource."
      redirect_back(fallback_location: root_path)
    end
  end

  # =====================================================
  # Private Methods
  # =====================================================
  private

  # Set Current.user for global access
  def set_current_user
    Current.user = current_user if defined?(Current)
  end

  # Set timezone based on user preference
  def set_timezone
    # Check if user exists and responds to time_zone
    if current_user && current_user.respond_to?(:time_zone)
      # Use the time_zone value if it exists, otherwise default to UTC
      time_zone = current_user.time_zone.presence || "UTC"
    else
      # If user doesn't exist or doesn't have time_zone, use UTC
      time_zone = "UTC"
    end
    
    Time.zone = time_zone
  end

  # Set agency theme in session
  def set_agency_theme
    return unless current_agency && current_agency.theme
    session[:agency_theme] = current_agency.theme
  end

  # Check for Turbo frame requests
  def check_for_turbo_frame
    @turbo_frame_request = request.headers["Turbo-Frame"].present?
  end

  # Handle record not found errors
  def handle_record_not_found
    respond_to do |format|
      format.html { redirect_to root_path, alert: "Record not found." }
      format.json { render json: { error: "Record not found" }, status: :not_found }
    end
  end

  # Handle missing parameters
  def handle_parameter_missing(exception)
    respond_to do |format|
      format.html { 
        redirect_back fallback_location: root_path, 
                     alert: "Missing parameter: #{exception.param}" 
      }
      format.json { 
        render json: { error: "Missing parameter: #{exception.param}" }, 
               status: :bad_request 
      }
    end
  end

  # =====================================================
  # Strong Parameters Helper
  # =====================================================
  
  # Helper for permitting nested attributes
  def permit_nested_attributes_for(model_class, attributes)
    params.require(model_class).permit(attributes)
  end
end