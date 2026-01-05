# app/policies/vehicle_policy.rb
class VehiclePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      # System admin sees everything
      return scope.all if user.system_admin?
      
      # Agency isolation: only see vehicles from user's agency
      if user.agency_id.present?
        scope.where(agency_id: user.agency_id)
      else
        scope.none  # Users without agency see nothing
      end
    end
  end

  # ====================
  # STANDARD CRUD ACTIONS
  # ====================
  
  def index?
    has_permission?("vehicles.view")
  end
  
  def show?
    has_permission?("vehicles.view") && same_agency?
  end
  
  def new?
    has_permission?("vehicles.create") && same_agency?
  end
  
  def create?
    has_permission?("vehicles.create") && same_agency?
  end
  
  def edit?
    has_permission?("vehicles.edit") && same_agency?
  end
  
  def update?
    has_permission?("vehicles.edit") && same_agency?
  end
  
  def destroy?
    has_permission?("vehicles.delete") && same_agency?
  end
  
  # ====================
  # CUSTOM ACTIONS
  # ====================
  
  def analytics?
    has_permission?("vehicles.view")  # Anyone who can view vehicles can see analytics
  end
  
  def maintenance_dashboard?
    has_permission?("maintenance.view") && same_agency?
  end
  
  def full_details?
    has_permission?("vehicles.view") && same_agency?
  end
  
  def trips?
    has_permission?("trips.view") && same_agency?
  end
  
  def report_issue?
    has_permission?("maintenance.create") && same_agency?
  end
  
  def export_csv?
    has_permission?("reports.export") && same_agency?
  end
  
  # ====================
  # GPS TRACKING ACTIONS
  # ====================
  
  def track_live?
    # Check basic permission
    return false unless has_permission?("tracking.live")
    return false unless same_agency?
    
    # Special handling for sensitive roles
    if user.requires_gps_approval?
      return user.gps_approved_for?(record, "live")
    end
    
    true
  end
  
  def tracking_history?
    return false unless has_permission?("tracking.history")
    return false unless same_agency?
    
    # Special handling for sensitive roles
    if user.requires_gps_approval?
      return user.gps_approved_for?(record, "history")
    end
    
    true
  end
  
  def replay_route?
    return false unless has_permission?("tracking.replay")
    return false unless same_agency?
    
    # Special handling for sensitive roles
    if user.requires_gps_approval?
      return user.gps_approved_for?(record, "replay")
    end
    
    true
  end
  
  # ====================
  # HELPER METHODS
  # ====================
  
  private
  
  def same_agency?
    return true if system_admin?
    return false unless record.respond_to?(:agency_id)
    
    # Check if vehicle belongs to user's agency
    if user.agency_id.present?
      record.agency_id == user.agency_id
    else
      false
    end
  end
end