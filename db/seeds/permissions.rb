# db/seeds/permissions.rb
PERMISSIONS = [
  # VEHICLES
  { key: "vehicles.view", category: "vehicles" },
  { key: "vehicles.create", category: "vehicles" },
  { key: "vehicles.edit", category: "vehicles" },
  { key: "vehicles.delete", category: "vehicles" },
  
  # TRIPS
  { key: "trips.view", category: "trips" },
  { key: "trips.create", category: "trips" },
  { key: "trips.edit", category: "trips" },
  { key: "trips.dispatch", category: "trips" },
  
  # GPS/TRACKING (SENSITIVE!)
  { key: "tracking.live", category: "tracking" },
  { key: "tracking.history", category: "tracking" },
  { key: "tracking.replay", category: "tracking" },
  { key: "tracking.geofences", category: "tracking" },
  
  # FUEL
  { key: "fuel.view", category: "fuel" },
  { key: "fuel.create", category: "fuel" },
  { key: "fuel.edit", category: "fuel" },
  
  # MAINTENANCE
  { key: "maintenance.view", category: "maintenance" },
  { key: "maintenance.create", category: "maintenance" },
  { key: "maintenance.edit", category: "maintenance" },
  
  # ADMIN
  { key: "users.manage", category: "admin" },
  { key: "roles.manage", category: "admin" },
  { key: "audit.view", category: "admin" }
]