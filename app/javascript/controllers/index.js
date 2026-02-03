// app/javascript/controllers/index.js
import { application } from "./application"

import VehicleCatalogController from "./vehicle_catalog_controller"
application.register("vehicle-catalog", VehicleCatalogController)

import FlashPopupController from "./flash_popup_controller"
application.register("flash-popup", FlashPopupController)


console.log("✅ Controllers registered (vehicle-catalog)")
