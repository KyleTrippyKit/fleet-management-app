# app/helpers/users_helper.rb
module UsersHelper
  def role_options_for_agency(agency_code)
    case agency_code
    when "VMCOTT"
      [
        ["Admin", "admin"],
        ["Billing Officer", "billing"],
        ["Finance Officer", "finance"],
        ["Receptionist", "receptionist"],
        ["Inspector", "inspector"],
        ["Parts Coordinator", "parts_coordinator"],
        ["Mechanic", "mechanic"],
        ["VMCOTT Staff", "vmcott_staff"],
        ["Clerk", "clerk"],
        ["Supervisor", "supervisor"]
      ]
    when "PTSC", "TTPS", "TTDF", "FIRE", "HEALTH", "EDUCATION"
      [
        ["Admin", "admin"],
        ["Fleet Manager", "fleet_manager"],
        ["Maintenance Supervisor", "maintenance_supervisor"],
        ["Finance Officer", "finance"],
        ["Driver", "driver"],
        ["Clerk", "clerk"],
        ["Supervisor", "supervisor"]
      ]
    else
      [
        ["Admin", "admin"],
        ["Fleet Manager", "fleet_manager"],
        ["Maintenance Supervisor", "maintenance_supervisor"],
        ["Finance Officer", "finance"],
        ["Driver", "driver"],
        ["Clerk", "clerk"],
        ["Supervisor", "supervisor"]
      ]
    end
  end
  
  def role_badge_color(role)
    case role
    when "admin"
      "bg-danger"
    when "finance", "billing"
      "bg-success"
    when "fleet_manager", "maintenance_supervisor"
      "bg-primary"
    when "receptionist", "inspector", "parts_coordinator", "mechanic"
      "bg-info"
    when "driver"
      "bg-warning"
    else
      "bg-secondary"
    end
  end
end