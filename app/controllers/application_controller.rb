# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  include Pundit::Authorization
  
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
  before_action :set_current_request
  before_action :set_timezone
  before_action :check_for_turbo_frame
  before_action :set_agency_theme
  before_action :prevent_real_payments_in_dev
  
  # ✅ ADDED: Set Current context for POS transactions
  around_action :set_current_context
  # ✅ ADDED: POS transaction current user setup
  around_action :set_pos_transaction_current_user, unless: :skip_pos_transaction_callback?

  # =====================================================
  # AFTER SIGN IN REDIRECT - THE FIX!
  # =====================================================
  # =====================================================
# AFTER SIGN IN REDIRECT - FIXED
# =====================================================
def after_sign_in_path_for(resource)
  Rails.logger.info "=== AFTER SIGN IN REDIRECT ==="
  Rails.logger.info "Resource class: #{resource.class}"
  Rails.logger.info "Resource inspect: #{resource.inspect}"

  # Handle case where resource might be an array
  user =
    if resource.is_a?(Array)
      Rails.logger.info "Resource is an array, trying to locate a user-like object..."
      resource.find { |r| r.respond_to?(:email) }
    else
      resource
    end

  # If we can't determine a user, fall back safely
  unless user&.respond_to?(:email)
    Rails.logger.error "No valid user object found for after_sign_in_path_for. Falling back."
    return "/main-dashboard"
  end

  Rails.logger.info "User: #{user.email}"
  Rails.logger.info "Agency: #{user.agency.inspect}"
  Rails.logger.info "Agency Code: #{user.agency&.code}"
  Rails.logger.info "Role: #{user.role}"
  Rails.logger.info "=============================="

  # ✅ Scanner users ALWAYS go to scanner home
  if user.respond_to?(:scanner_role?) && user.scanner_role?
    Rails.logger.info "Scanner user detected -> redirecting to scanner_home_path"
    return scanner_home_path
  end

  # Respect stored location for non-scanner users (e.g., they tried to open a page before login)
  stored = stored_location_for(user)
  if stored.present?
    Rails.logger.info "Stored location found -> redirecting to #{stored}"
    return stored
  end

  # Otherwise route by agency code
  case user.agency&.code
  when "PTSC"  then "/ptsc-dashboard"
  when "VMCOTT" then "/vmcott-dashboard"
  when "TTPS"  then "/ttps-dashboard"
  when "TTDF"  then "/ttdf-dashboard"
  else              "/main-dashboard"
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
                :can_access_pos?,
                :can_open_register?,
                :can_void_transactions?,
                :can_refund_transactions?,
                :is_ptsc?,
                :can_view_reports?,
                :can_close_register?,
                :invoice_status_badge_color

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

  # Check if user belongs to PTSC agency
  def is_ptsc?
    current_agency&.code == 'PTSC'
  end

  # Get current user role
  def current_user_role
    current_user&.role || 'guest'
  end

  # POS permissions
  def can_access_pos?
    current_user&.can_access_pos? || false
  end

  def can_open_register?
    current_user&.can_open_register? || false
  end

  def can_close_register?
    current_user&.can_close_register? || false
  end

  def can_void_transactions?
    current_user&.can_void_transactions? || false
  end

  def can_refund_transactions?
    current_user&.can_refund_transactions? || false
  end

  def can_view_reports?
    current_user&.can_view_reports? || false
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

  # Badge color for invoice status
  def invoice_status_badge_color(status)
    case status
    when 'paid' then 'success'
    when 'reviewed' then 'info'
    when 'pending' then 'warning'
    when 'disputed' then 'danger'
    else 'secondary'
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

  # =====================================================
  # Authorization Methods
  # =====================================================
  
  def require_vmcott_user
    return if current_user.admin?
    
    unless vmcott?
      redirect_to root_path, alert: 'Access denied. VMCOTT users only.'
    end
  end
  
  # POS Authorization Methods
  def require_pos_access
    unless can_access_pos?
      redirect_to root_path, alert: 'You do not have permission to access the POS system'
    end
  end

  def authorize_pos_void!
    unless can_void_transactions?
      redirect_to root_path, alert: 'You do not have permission to void transactions'
    end
  end

  def authorize_pos_refund!
    unless can_refund_transactions?
      redirect_to root_path, alert: 'You do not have permission to refund transactions'
    end
  end

  def authorize_open_register!
    unless can_open_register?
      redirect_to root_path, alert: 'You do not have permission to open the cash register'
    end
  end

  def authorize_close_register!
    unless can_close_register?
      redirect_to root_path, alert: 'You do not have permission to close the cash register'
    end
  end

  def authorize_view_reports!
    unless can_view_reports?
      redirect_to root_path, alert: 'You do not have permission to view reports'
    end
  end

  def authorize_ptsc_pos!
    return if is_ptsc?
    redirect_to root_path, alert: 'PTSC POS features are only available to PTSC staff'
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
  # Private Methods
  # =====================================================
  private

  # NEW: Check if we should skip POS transaction callback
  def skip_pos_transaction_callback?
    # Skip for vmcott parts edit action to prevent template errors
    controller_path == 'vmcott/parts' && action_name == 'edit'
  end

  # Set Current context
  def set_current_context
    Current.with(current_user, request) do
      yield
    end
  end

  # Set current user
  def set_current_user
    Current.user = current_user
  end

  # Set current request
  def set_current_request
    Current.set_request(request)
  end
  
  # ✅ ADDED: Set current user for POS transactions
  def set_pos_transaction_current_user
    if defined?(PosTransaction)
      PosTransaction.with_current_user(current_user) do
        yield
      end
    else
      yield
    end
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
  
  # Prevent real payments in development environment
  def prevent_real_payments_in_dev
    if Rails.env.development? && params[:controller] == 'purchase_orders' && 
       ['process_payment', 'authorize_payment'].include?(params[:action])
      # Log but don't process real payments
      Rails.logger.info "MOCK PAYMENT: #{params.inspect}"
      @mock_result = { success: true, transaction_id: "MOCK-#{SecureRandom.hex(8)}" }
    end
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