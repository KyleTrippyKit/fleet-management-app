// File: app/javascript/controllers/application.js
import { Application } from "@hotwired/stimulus"

const application = Application.start()

// Expose globally (so we can debug in console)
window.Stimulus = application

console.log("✅ Stimulus started")

export { application }
