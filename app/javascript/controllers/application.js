import { Application } from "@hotwired/stimulus"
import "@hotwired/turbo-rails"
import "controllers"

console.log("Application loaded")

const application = Application.start()

// Configure Stimulus development experience
application.debug = false
window.Stimulus   = application

export { application }
