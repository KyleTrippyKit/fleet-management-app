// app/javascript/application.js - FINAL WORKING VERSION

// Import Stimulus
import { Application } from "@hotwired/stimulus"

import "chartjs-adapter-date-fns"
window.Chart = Chart

// Initialize Stimulus
const application = Application.start()

// Manually register controllers (Import Maps doesn't auto-load)
// Add ALL your controllers here:

// 1. Chart controller (most important!)
import ChartController from "./controllers/chart_controller"
application.register("chart", ChartController)

// 2. Add other controllers if you have them:
// import OtherController from "./controllers/other_controller"
// application.register("other", OtherController)

// Make globally available
window.Stimulus = application

console.log("✅ Stimulus Application started")
console.log("✅ Registered controllers:", Array.from(application.router.modules.keys()))