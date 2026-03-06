# app/helpers/users_helper.rb
module UsersHelper
  def role_options_for_agency(agency_code)
    case agency_code
    when "VMCOTT"
      [
        ["Admin", "admin"],
        ["Security Gate Officer", "security_gate_officer"],  # ← UPDATE THIS
        ["Inspector", "inspector"],
        ["Inventory Manager", "inventory_manager"],          # ← UPDATE THIS
        ["Procurement", "procurement"],                      # ← UPDATE THIS
        ["Finance Officer", "finance"],
        ["Mechanic", "mechanic"],
        ["Workshop Supervisor", "workshop_supervisor"],
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
    when "finance"
      "bg-success"
    when "procurement", "billing"  # Keep backward compatibility
      "bg-success"
    when "fleet_manager", "maintenance_supervisor"
      "bg-primary"
    when "security_gate_officer", "receptionist"  # Keep backward compatibility
      "bg-info"
    when "inspector"
      "bg-info"
    when "inventory_manager", "parts_coordinator"  # Keep backward compatibility
      "bg-info"
    when "mechanic"
      "bg-info"
    when "driver"
      "bg-warning"
    else
      "bg-secondary"
    end
  end
end