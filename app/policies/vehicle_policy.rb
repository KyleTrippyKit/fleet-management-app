# app/policies/vehicle_policy.rb
class VehiclePolicy
  attr_reader :user, :vehicle
  
  def initialize(user, vehicle)
    @user = user
    @vehicle = vehicle
  end
  
  def index?
    user.present?  # Any logged-in user can see index
  end
  
  def show?
    # User can see vehicle if they belong to the same agency
    user.agency_id == vehicle.agency_id
  end
  
  def create?
    user.fleet_manager? || user.admin?
  end
  
  def update?
    user.fleet_manager? || user.admin? || 
    (user.maintenance_supervisor? && vehicle.service_owner == 'PTSC')
  end
  
  def destroy?
    user.admin?  # Only admins can delete
  end
  
  # Scope for what vehicles a user can see
  class Scope
    attr_reader :user, :scope
    
    def initialize(user, scope)
      @user = user
      @scope = scope
    end
    
    def resolve
      if user.admin?
        scope.all  # Admins see everything
      else
        scope.where(agency_id: user.agency_id)  # Only own agency
      end
    end
  end
end