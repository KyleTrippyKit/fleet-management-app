// app/javascript/controllers/application.js
import { Application } from "@hotwired/stimulus"

export const application = Application.start()
window.Stimulus = application

// Optional debug:
// application.debug = true

console.log("✅ Stimulus started")
