// app/javascript/controllers/index.js
import { application } from "./application"

import VehicleCatalogController from "./vehicle_catalog_controller"
application.register("vehicle-catalog", VehicleCatalogController)

console.log("✅ Controllers registered (vehicle-catalog)")
