// =====================================================
// ✅ CORRECT IMPORTMAP-COMPATIBLE STIMULUS SETUP
// =====================================================

import { Application } from "@hotwired/stimulus"

console.log("🚀 Stimulus initializing...")

// Start ONE Stimulus app
const application = Application.start()
application.debug = true

// Make global (important for Turbo + debugging)
window.Stimulus = application

console.log("✅ Stimulus started")

// =====================================================
// ✅ IMPORT CONTROLLERS USING IMPORTMAP PATHS
// =====================================================

import HelloController from "controllers/hello_controller"
import ExampleController from "controllers/example_controller"
import SearchController from "controllers/search_controller"
import DriverSearchController from "controllers/driver_search_controller"
import FleetIndexController from "controllers/fleet_index_controller"
import ImagePreviewController from "controllers/image_preview_controller"
import InactivityController from "controllers/inactivity_controller"
import LoadingButtonController from "controllers/loading_button_controller"
import InvoiceSearchController from "controllers/invoice_search_controller"
import AgencyAssignController from "controllers/agency_assign_controller"
import SupplierSelectController from "controllers/supplier_select_controller"
import QuotationVehicleSearchController from "controllers/quotation_vehicle_search_controller"
import AlertSearchController from "controllers/alert_search_controller"
import VehicleCatalogController from "controllers/vehicle_catalog_controller"
import ChartController from "controllers/chart_controller"

console.log("📝 Controllers imported, registering...")

// =====================================================
// ✅ REGISTER CONTROLLERS
// =====================================================

const controllers = [
  ["hello", HelloController],
  ["example", ExampleController],
  ["search", SearchController],
  ["driver-search", DriverSearchController],
  ["fleet-index", FleetIndexController],
  ["image-preview", ImagePreviewController],
  ["inactivity", InactivityController],
  ["loading-button", LoadingButtonController],
  ["invoice-search", InvoiceSearchController],
  ["agency-assign", AgencyAssignController],
  ["supplier-select", SupplierSelectController],
  ["quotation-vehicle-search", QuotationVehicleSearchController],
  ["alert-search", AlertSearchController],
  ["vehicle-catalog", VehicleCatalogController],
  ["chart", ChartController]
]

controllers.forEach(([name, controller]) => {
  application.register(name, controller)
  console.log(`✅ Registered: ${name}`)
})

console.log(`✅ Total controllers: ${controllers.length}`)

// =====================================================
// ✅ DEBUG AFTER TURBO LOAD
// =====================================================

document.addEventListener("turbo:load", () => {
  const connected = application.controllers.map(c => c.identifier)
  console.log("🔗 Connected controllers:", connected)
  console.log(`📊 Connected count: ${connected.length}`)
})

export { application }