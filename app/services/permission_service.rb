# app/services/permission_service.rb
class PermissionService
  def initialize(user, resource = nil)
    @user = user
    @resource = resource
  end
  
  def can?(action)
    case action
    when :view_vehicle
      can_view_vehicle?
    when :edit_vehicle
      can_edit_vehicle?
    when :delete_vehicle
      can_delete_vehicle?
    when :view_analytics
      can_view_analytics?
    when :view_maintenance
      can_view_maintenance?
    when :report_issue
      can_report_issue?
    else
      false
    end
  end
  
  private
  
  def can_view_vehicle?
    return false unless @user
    return true if @user.admin?
    
    # ✅ ADD THIS: Security Gate Officers can view vehicles
    return true if @user.security_gate_officer?
    
    # VMCOTT users can view all vehicles
    return true if @user.vmcott?
    
    # Check if resource exists and belongs to user's agency
    if @resource
      @resource.agency_id == @user.agency_id
    else
      # For general view permission (index action)
      true
    end
  end
  
  def can_edit_vehicle?
    return false unless @user
    return true if @user.admin?
    
    # ❌ Security Gate Officers cannot edit vehicles
    return false if @user.security_gate_officer?
    
    # Fleet managers can edit vehicles in their agency
    if @user.fleet_manager? && @resource
      @resource.agency_id == @user.agency_id
    else
      false
    end
  end
  
  def can_delete_vehicle?
    return false unless @user
    # ❌ Security Gate Officers cannot delete vehicles
    return false if @user.security_gate_officer?
    # Only admins can delete vehicles
    @user.admin?
  end
  
  def can_view_analytics?
    return false unless @user
    # ❌ Security Gate Officers cannot view analytics
    return false if @user.security_gate_officer?
    # Fleet managers, finance, and admins can view analytics
    @user.fleet_manager? || @user.finance? || @user.admin? || @user.manager?
  end
  
  def can_view_maintenance?
    return false unless @user
    # ❌ Security Gate Officers cannot view maintenance
    return false if @user.security_gate_officer?
    # Maintenance roles and fleet managers can view maintenance
    @user.maintenance_supervisor? || @user.fleet_manager? || @user.admin? || @user.manager?
  end
  
  def can_report_issue?
    return false unless @user
    # Security Gate Officers can report issues (they see damage during check-in)
    return true if @user.security_gate_officer?
    # Drivers and maintenance roles can report issues
    @user.driver? || @user.maintenance_supervisor? || @user.fleet_manager? || @user.admin?
  end
end