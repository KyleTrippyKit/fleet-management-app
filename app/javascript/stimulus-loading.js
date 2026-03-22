import { Application } from "@hotwired/stimulus"

const application = Application.start()

// Configure Stimulus development experience
application.debug = true  // Set to true temporarily for debugging
window.Stimulus = application

export { application }
