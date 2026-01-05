# app/policies/application_policy.rb
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      # Default: No access
      scope.none
    end
  end

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  # ====================
  # TRINIDAD-SPECIFIC HELPERS
  # ====================
  
  protected
  
  def same_agency?
    return true if user&.system_admin?
    return false unless record.respond_to?(:agency_id)
    return false unless user&.agency_id.present?
    
    record.agency_id == user.agency_id
  end
  
  def agency_admin?
    user&.has_permission?("users.manage") || user&.system_admin?
  end
  
  def emergency_override?
    # Check if user has emergency override active
    user&.emergency_override_active?
  end
  
  def log_access(action, outcome: "granted", details: {})
    user&.log_access(action, record, outcome: outcome, details: details)
  end
  
  # Permission helpers
  def has_permission?(permission_key)
    user&.has_permission?(permission_key)
  end
  
  # Role helpers
  def system_admin?
    user&.system_admin?
  end
  
  def fleet_manager?
    user&.fleet_manager?
  end
  
  def dispatcher?
    user&.dispatcher?
  end
  
  def driver?
    user&.driver?
  end
  
  def cid_investigator?
    user&.cid_user?
  end
  
  def traffic_officer?
    user&.traffic_police?
  end
  
  def auditor?
    user&.auditor?
  end
  
  def ptsc_user?
    user&.ptsc_user?
  end
  
  def police_user?
    user&.police_user?
  end
end