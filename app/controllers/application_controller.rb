# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  # =====================================================
  # Pundit
  # =====================================================
  include Pundit::Authorization

  # Only allow modern browsers
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag
  stale_when_importmap_changes

  # Include all helpers
  helper :all

  # =====================================================
  # Before Actions
  # =====================================================
  before_action :set_current_user

  # =====================================================
  # Pundit Callbacks
  # =====================================================
  after_action :verify_authorized, unless: :skip_pundit?
  after_action :verify_policy_scoped, only: :index, unless: :skip_pundit?

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  # =====================================================
  # Helper Methods
  # =====================================================
  helper_method :current_company, :owner_color, :urgency_badge_class,
                :status_badge_class, :format_date, :format_currency,
                :admin?, :manager?, :current_user_role

  # =====================================================
  # Pundit helpers
  # =====================================================
  def skip_pundit?
    devise_controller?
  end

  # =====================================================
  # Company
  # =====================================================
  def current_company
    @current_company ||= current_user&.company
  end

  # =====================================================
  # UI Helpers
  # =====================================================
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

  def urgency_badge_class(urgency)
    case urgency.to_s.downcase
    when 'emergency' then 'bg-danger text-white'
    when 'scheduled' then 'bg-warning text-dark'
    when 'routine' then 'bg-primary text-white'
    else 'bg-secondary text-white'
    end
  end

  def status_badge_class(status)
    case status.to_s.downcase
    when 'completed' then 'bg-success text-white'
    when 'pending' then 'bg-warning text-dark'
    when 'cancelled' then 'bg-secondary text-white'
    else 'bg-info text-white'
    end
  end

  def format_date(date, format: :medium)
    return "N/A" unless date

    case format
    when :short then date.strftime("%Y-%m-%d")
    when :medium then date.strftime("%b %d, %Y")
    when :long then date.strftime("%B %d, %Y")
    when :with_time then date.strftime("%Y-%m-%d %H:%M")
    else date.strftime("%Y-%m-%d")
    end
  end

  def format_currency(amount, currency: "TTD")
    return "N/A" unless amount
    number_to_currency(amount, unit: "$", separator: ".", delimiter: ",")
  end

  # =====================================================
  # Role helpers
  # =====================================================
  def admin?
    current_user&.role == 'admin'
  end

  def manager?
    admin? || current_user&.role == 'manager'
  end

  def current_user_role
    current_user&.role || 'guest'
  end

  # =====================================================
  # Error Handling
  # =====================================================
  def user_not_authorized
    redirect_back fallback_location: root_path,
                  alert: "You are not authorized to perform this action."
  end

  rescue_from ActiveRecord::RecordNotFound do
    redirect_to root_path, alert: "Record not found."
  end

  rescue_from ActionController::ParameterMissing do |e|
    redirect_back fallback_location: root_path,
                  alert: "Missing parameter: #{e.param}"
  end

  # =====================================================
  # Private
  # =====================================================
  private

  def set_current_user
    Current.user = current_user if defined?(Current)
  end
end
