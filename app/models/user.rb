# app/models/user.rb
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :trackable

  # Trinidad RBAC Associations
  belongs_to :agency, optional: true
  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles
  has_many :agencies, through: :user_roles

  # GPS Approvals
  has_many :gps_access_approvals, dependent: :destroy
  has_many :approved_gps_accesses, -> { where(status: 'approved') }, 
           class_name: 'GpsAccessApproval'

  # Access Logs
  has_many :access_logs, dependent: :nullify

  # Validations for government users
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :email, presence: true, uniqueness: true
  validates :password, length: { minimum: 8 }, if: -> { new_record? || !password.nil? }
  validates :employee_id, presence: true, if: :government_user?
  validates :agency_id, presence: true, if: :government_user?

  # Scopes
  scope :active, -> { where(is_active: true) }
  scope :by_agency, ->(agency) { where(agency: agency) }
  scope :with_role, ->(role_name) { joins(:roles).where(roles: { name: role_name }) }

  # ====================
  # PERMISSION METHODS
  # ====================
  
  def has_permission?(permission_key)
    return true if system_admin? # System admins have all permissions
    
    # Get all permissions from user's roles
    role_ids = user_roles.pluck(:role_id)
    return false if role_ids.empty?
    
    # Check if any role has this permission
    Permission.joins(:roles)
              .where(roles: { id: role_ids })
              .where(key: permission_key)
              .exists?
  end
  
  def permissions
    return Permission.all if system_admin?
    
    Permission.joins(:roles)
              .where(roles: { id: user_roles.pluck(:role_id) })
              .distinct
  end
  
  def permission_keys
    permissions.pluck(:key)
  end

  # ====================
  # Agency & Role Checks
  # ====================
  
  def system_admin?
    roles.where(is_system_admin: true).exists?
  end

  def ptsc_user?
    agency&.code == "PTSC"
  end

  def police_user?
    agency&.code == "TTPS"
  end

  def cid_user?
    police_user? && roles.where(name: "TTPS CID Investigator").exists?
  end

  def traffic_police?
    police_user? && roles.where(name: "TTPS Traffic Officer").exists?
  end

  def requires_gps_approval?
    roles.where(requires_gps_approval: true).exists?
  end

  def fleet_manager?
    roles.where(name: ["PTSC Fleet Manager", "TTPS Fleet Commander"]).exists?
  end

  def dispatcher?
    roles.where(name: ["PTSC Dispatcher", "TTPS Dispatcher"]).exists?
  end

  def driver?
    roles.where(name: "PTSC Driver").exists?
  end

  def auditor?
    roles.where(name: ["PTSC Auditor", "TTPS Auditor"]).exists?
  end

  # ====================
  # GPS Access
  # ====================
  
  def can_access_gps?(vehicle, access_type = "live")
    return true if system_admin?
    return false unless vehicle.agency_id == agency_id
    
    case access_type
    when "live"
      track_live?(vehicle)
    when "history"
      view_history?(vehicle)
    when "replay"
      replay_route?(vehicle)
    else
      false
    end
  end
  
  def track_live?(vehicle)
    return false unless has_permission?("tracking.live")
    return true unless requires_gps_approval?
    
    gps_approved_for?(vehicle, "live")
  end
  
  def view_history?(vehicle)
    return false unless has_permission?("tracking.history")
    return true unless requires_gps_approval?
    
    gps_approved_for?(vehicle, "history")
  end
  
  def replay_route?(vehicle)
    return false unless has_permission?("tracking.replay")
    return true unless requires_gps_approval?
    
    gps_approved_for?(vehicle, "replay")
  end

  def gps_approved_for?(vehicle, access_type = "live")
    approved_gps_accesses.where(
      vehicle: vehicle,
      access_type: access_type
    ).where("expires_at > ?", Time.current).exists?
  end

  def request_gps_access(vehicle, access_type, reason)
    GpsAccessApproval.create(
      user: self,
      vehicle: vehicle,
      access_type: access_type,
      reason: reason,
      status: 'pending'
    )
  end

  # ====================
  # LOGGING
  # ====================
  
  def log_access(action, resource = nil, outcome: "granted", details: {})
    # Check if AccessLog table exists first
    return true unless AccessLog.table_exists?
    
    begin
      AccessLog.create(
        user: self,
        agency: agency,
        action: action,
        resource: resource,
        ip_address: current_sign_in_ip,
        user_agent: current_sign_in_ip.present? ? "API" : "Web",
        details: details,
        outcome: outcome,
        accessed_at: Time.current
      )
    rescue => e
      # Log error but don't break the application
      Rails.logger.error "Failed to log access: #{e.message}"
      nil
    end
  end

  # ====================
  # HELPERS
  # ====================
  
  def display_name
    full_name.presence || email.split('@').first.titleize
  end

  def government_user?
    agency_id.present?
  end

  def active_for_authentication?
    super && is_active?
  end

  def inactive_message
    is_active? ? super : "Your account has been deactivated. Please contact your administrator."
  end

  def update_login_stats
    update(
      last_login_at: Time.current,
      login_count: login_count.to_i + 1
    )
  end

  def accessible_vehicles
    if system_admin?
      Vehicle.all
    elsif agency
      Vehicle.where(agency: agency)
    else
      Vehicle.none
    end
  end

  def accessible_trips
    if system_admin?
      Trip.all
    elsif agency
      Trip.joins(:vehicle).where(vehicles: { agency: agency })
    else
      Trip.none
    end
  end
  
  # Primary agency (for users with multiple agencies)
  def primary_agency
    agency
  end
  
  def primary_agency_id
    agency_id
  end
  
  # Emergency override (for special situations)
  def emergency_override_active?
    # Implement based on your requirements
    false
  end
end