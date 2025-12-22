class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Include all helpers
  helper :all

  # =====================================================
  # Before Actions
  # =====================================================
  before_action :set_current_user

  # =====================================================
  # Helper Methods
  # =====================================================
  helper_method :current_company, :owner_color, :urgency_badge_class, 
                :status_badge_class, :format_date, :format_currency,
                :admin?, :manager?, :current_user_role

  # Get current company/organization
  def current_company
    @current_company ||= current_user&.company
  end

  # Color coding for service owners
  def owner_color(owner)
    case owner.to_s.downcase
    when 'ptsc' then 'primary'
    when 'police' then 'danger'
    when 'fire service', 'fire' then 'warning'
    when 'ambulance', 'medical' then 'info'
    when 'government' then 'secondary'
    else 'dark'
    end
  end

  # Badge class for maintenance urgency
  def urgency_badge_class(urgency)
    case urgency.to_s.downcase
    when 'emergency' then 'bg-danger text-white'
    when 'scheduled' then 'bg-warning text-dark'
    when 'routine' then 'bg-primary text-white'
    else 'bg-secondary text-white'
    end
  end

  # Badge class for maintenance status
  def status_badge_class(status)
    case status.to_s.downcase
    when 'completed' then 'bg-success text-white'
    when 'pending' then 'bg-warning text-dark'
    when 'cancelled' then 'bg-secondary text-white'
    else 'bg-info text-white'
    end
  end

  # Format date consistently
  def format_date(date, format: :medium)
    return "N/A" unless date
    
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
    return "N/A" unless amount
    number_to_currency(amount, unit: "$", separator: ".", delimiter: ",")
  end

  # Authorization helpers
  def admin?
    current_user&.role == 'admin'
  end

  def manager?
    current_user&.role == 'manager' || admin?
  end

  def current_user_role
    current_user&.role || 'guest'
  end

  # =====================================================
  # Pagination Settings
  # =====================================================
  def per_page
    params[:per_page] || 20
  end

  # =====================================================
  # Error Handling
  # =====================================================
  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
  rescue_from ActionController::ParameterMissing, with: :parameter_missing

  def record_not_found
    respond_to do |format|
      format.html { redirect_to root_path, alert: "Record not found." }
      format.json { render json: { error: "Record not found" }, status: :not_found }
    end
  end

  def parameter_missing(exception)
    respond_to do |format|
      format.html { redirect_back fallback_location: root_path, alert: "Missing parameter: #{exception.param}" }
      format.json { render json: { error: "Missing parameter: #{exception.param}" }, status: :bad_request }
    end
  end

  # Simple authorization error
  def access_denied(message = "You are not authorized to perform this action.")
    respond_to do |format|
      format.html { redirect_to root_path, alert: message }
      format.json { render json: { error: message }, status: :forbidden }
    end
  end

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

  def set_current_user
    Current.user = current_user if defined?(Current)
  end

  # Strong parameters for nested attributes
  def permit_nested_attributes_for(model_class, attributes)
    params.require(model_class).permit(attributes)
  end

  # Timezone handling
  def set_timezone
    Time.zone = current_user&.time_zone || "UTC"
  end

  # =====================================================
  # Breadcrumbs
  # =====================================================
  def add_breadcrumb(name, path = nil)
    @breadcrumbs ||= []
    @breadcrumbs << { name: name, path: path }
  end

  # =====================================================
  # Authorization (Simple implementation without CanCanCan)
  # =====================================================
  def authorize_admin!
    unless admin?
      access_denied("Administrator access required.")
    end
  end

  def authorize_manager!
    unless manager?
      access_denied("Manager access required.")
    end
  end

  # Check if user can manage a specific resource
  def authorize_owner!(resource)
    return if admin?
    return if resource.user_id == current_user.id
    return if resource.respond_to?(:created_by) && resource.created_by == current_user.id
    
    access_denied("You don't have permission to manage this resource.")
  end

  # Check if user can view a specific resource
  def authorize_viewer!(resource)
    # Admin and managers can view everything
    return if admin? || manager?
    
    # Regular users can only view their own resources
    if resource.respond_to?(:user_id) && resource.user_id != current_user.id
      access_denied("You don't have permission to view this resource.")
    end
  end
end