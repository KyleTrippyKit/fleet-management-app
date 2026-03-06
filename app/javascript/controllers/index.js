// File: app/javascript/controllers/index.js
//
// TEST MODE: explicit registration (no auto loader guessing)
// This file MUST run, or Stimulus will show but controllers won't.
//

import { application } from "./application"

import VehicleCatalogController from "./vehicle_catalog_controller"
application.register("vehicle-catalog", VehicleCatalogController)

import LoadingButtonController from "./loading_button_controller"
application.register("loading-button", LoadingButtonController)

import FleetIndexController from "./fleet_index_controller"
application.register("fleet-index", FleetIndexController)

import AlertSearchController from "./alert_search_controller"
application.register("alert-search", AlertSearchController)

import "channels"

import QuotationVehicleSearchController from "./quotation_vehicle_search_controller"
application.register("quotation-vehicle-search", QuotationVehicleSearchController)

// Import and register the supplier select controller
import SupplierSelectController from "./supplier_select_controller"
application.register("supplier-select", SupplierSelectController)

// Import and register the inactivity controller for screensaver
import InactivityController from "./inactivity_controller"
application.register("inactivity", InactivityController)

console.log("✅ Controllers registered:", application.controllers)
console.log("   • vehicle-catalog")
console.log("   • loading-button")
console.log("   • fleet-index")
console.log("   • alert-search")
console.log("   • quotation-vehicle-search")
console.log("   • supplier-select")
console.log("   • inactivity (screensaver)")