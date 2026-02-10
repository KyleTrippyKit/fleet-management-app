// app/javascript/controllers/index.js
import { application } from "./application"

import VehicleCatalogController from "./vehicle_catalog_controller"
application.register("vehicle-catalog", VehicleCatalogController)

import LoadingButtonController from "./loading_button_controller"
application.register("loading-button", LoadingButtonController)

import FleetIndexController from "./fleet_index_controller"
application.register("fleet-index", FleetIndexController)

import AlertSearchController from "./alert_search_controller"
application.register("alert-search", AlertSearchController)

console.log("✅ Controllers registered (vehicle-catalog)")
