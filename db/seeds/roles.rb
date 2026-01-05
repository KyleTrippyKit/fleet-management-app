# db/seeds/roles.rb
ROLES = {
  # === VMCOTT (System) ===
  "System Administrator" => {
    category: "system",
    is_system_admin: true,
    permissions: Permission.pluck(:key)  # All permissions
  },
  
  # === PTSC ROLES ===
  "PTSC Director" => {
    category: "admin",
    permissions: [
      "vehicles.*", "trips.*", "tracking.*", 
      "fuel.*", "maintenance.*", "users.manage"
    ]
  },
  
  "PTSC Fleet Manager" => {
    category: "operations",
    permissions: [
      "vehicles.view", "vehicles.create", "vehicles.edit",
      "trips.view", "trips.create", "trips.edit", "trips.dispatch",
      "tracking.live", "tracking.history", "tracking.replay",
      "fuel.view", "fuel.create", "fuel.edit",
      "maintenance.view", "maintenance.create", "maintenance.edit"
    ]
  },
  
  "PTSC Dispatcher" => {
    category: "operations",
    permissions: [
      "vehicles.view",
      "trips.view", "trips.create", "trips.dispatch",
      "tracking.live", "tracking.history"
    ]
  },
  
  "PTSC Driver" => {
    category: "driver",
    permissions: ["vehicles.view", "trips.view"]
  },
  
  # === POLICE (TTPS) ROLES ===
  "TTPS Fleet Commander" => {
    category: "admin",
    permissions: [
      "vehicles.view", "vehicles.create", "vehicles.edit",
      "trips.view", "trips.create", "trips.edit",
      "tracking.live", "tracking.history", "tracking.replay",
      "fuel.view", "fuel.create", "fuel.edit",
      "maintenance.view", "maintenance.create", "maintenance.edit"
    ]
  },
  
  "TTPS Dispatcher" => {
    category: "operations",
    permissions: [
      "vehicles.view",
      "trips.view", "trips.create", "trips.dispatch",
      "tracking.live", "tracking.history"
    ]
  },
  
  "TTPS Traffic Officer" => {
    category: "operations",
    requires_gps_approval: true,  # Needs approval for live tracking
    permissions: [
      "vehicles.view",
      "trips.view",
      "tracking.live",  # Requires approval
      "tracking.history"
    ]
  },
  
  "TTPS CID Investigator" => {
    category: "investigations",
    requires_gps_approval: true,  # Always requires approval
    permissions: [
      "vehicles.view",
      "trips.view",
      "tracking.live", "tracking.history", "tracking.replay"
    ]
  },
  
  "TTPS Auditor" => {
    category: "auditor",
    permissions: [
      "vehicles.view",
      "trips.view",
      "tracking.history", "tracking.replay",
      "fuel.view",
      "maintenance.view",
      "audit.view"
    ]
  }
}