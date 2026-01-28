// app/javascript/application.js

// Import jQuery first
import "jquery"

// Import Bootstrap JavaScript
import "bootstrap"

// Import Stimulus
import { Application } from "@hotwired/stimulus"

// Import Turbo and Cocoon
import "@hotwired/turbo-rails"
import "@nathanvda/cocoon"

// Make jQuery globally available
window.$ = window.jQuery = jQuery

// Initialize Stimulus
const application = Application.start()
window.Stimulus = application

console.log("✅ Application loaded with Bootstrap, jQuery, Stimulus, Turbo, Cocoon")

// Bootstrap is now available globally via the import
// The bundle includes Popper.js automatically

// Initialize Bootstrap components when Turbo loads
document.addEventListener('turbo:load', () => {
  // Tooltips
  const tooltipTriggerList = document.querySelectorAll('[data-bs-toggle="tooltip"]')
  tooltipTriggerList.forEach(tooltipTriggerEl => {
    new bootstrap.Tooltip(tooltipTriggerEl)
  })
  
  // Popovers
  const popoverTriggerList = document.querySelectorAll('[data-bs-toggle="popover"]')
  popoverTriggerList.forEach(popoverTriggerEl => {
    new bootstrap.Popover(popoverTriggerEl)
  })
  
  // CSRF Token
  const csrfToken = document.querySelector('meta[name="csrf-token"]')
  if (csrfToken) {
    window.csrfToken = csrfToken.content
  }
})

// CSRF Token for Turbo requests
document.addEventListener('turbo:before-fetch-request', (event) => {
  const token = window.csrfToken || document.querySelector('meta[name="csrf-token"]')?.content
  if (token) {
    event.detail.fetchOptions.headers['X-CSRF-Token'] = token
  }
})

// Check if libraries loaded
document.addEventListener('DOMContentLoaded', function() {
  console.log("✅ DOM fully loaded")
  
  if (typeof bootstrap !== 'undefined') {
    console.log("✅ Bootstrap loaded successfully")
  } else {
    console.error("❌ Bootstrap not loaded")
  }
  
  if (typeof window.$ !== 'undefined') {
    console.log("✅ jQuery loaded successfully")
  } else {
    console.error("❌ jQuery failed to load")
  }
})

export { application }