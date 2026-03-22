// Import and register all your controllers from the importmap under controllers/*
import { application } from "../stimulus-loading"

// Import all controllers
import AgencyAssignController from "./agency_assign_controller"
import AlertSearchController from "./alert_search_controller"
import ChartController from "./chart_controller"
import DriverSearchController from "./driver_search_controller"
import ExampleController from "./example_controller"
import FleetIndexController from "./fleet_index_controller"
import HelloController from "./hello_controller"
import ImagePreviewController from "./image_preview_controller"
import InactivityController from "./inactivity_controller"
import LoadingButtonController from "./loading_button_controller"
import QuotationVehicleSearchController from "./quotation_vehicle_search_controller"
import SearchController from "./search_controller"
import SupplierSelectController from "./supplier_select_controller"
import VehicleCatalogController from "./vehicle_catalog_controller"

// Register all controllers
application.register("agency-assign", AgencyAssignController)
application.register("alert-search", AlertSearchController)
application.register("chart", ChartController)
application.register("driver-search", DriverSearchController)
application.register("example", ExampleController)
application.register("fleet-index", FleetIndexController)
application.register("hello", HelloController)
application.register("image-preview", ImagePreviewController)
application.register("inactivity", InactivityController)
application.register("loading-button", LoadingButtonController)
application.register("quotation-vehicle-search", QuotationVehicleSearchController)
application.register("search", SearchController)
application.register("supplier-select", SupplierSelectController)
application.register("vehicle-catalog", VehicleCatalogController)

console.log("✅ Stimulus controllers registered successfully")
