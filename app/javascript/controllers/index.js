// app/javascript/controllers/index.js
import { application } from "./application"

import VehicleCatalogController from "./vehicle_catalog_controller"
application.register("vehicle-catalog", VehicleCatalogController)

// register other controllers here when needed
