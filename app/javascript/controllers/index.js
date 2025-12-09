// app/javascript/controllers/index.js
import { application } from "controllers/application"

// Explicitly import your chart controller
import ChartController from "./chart_controller"

// Register your chart controller with the application
application.register("chart", ChartController)

// Import and register all your controllers from the importmap via controllers/**/*_controller
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)

import ImagePreviewController from "./image_preview_controller"
application.register("image-preview", ImagePreviewController)

