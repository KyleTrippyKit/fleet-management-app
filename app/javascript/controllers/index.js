// app/javascript/controllers/index.js
import { application } from "./application"

import VehicleCatalogController from "./vehicle_catalog_controller"
application.register("vehicle-catalog", VehicleCatalogController)

import LoadingButtonController from "./loading_button_controller"
application.register("loading-button", LoadingButtonController)

import FleetIndexController from "./fleet_index_controller"
application.register("fleet-index", FleetIndexController)

console.log("✅ Controllers registered (vehicle-catalog)")
