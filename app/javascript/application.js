// app/javascript/application.js
// Import dependencies 
import "jquery"  // <-- jQuery first (cocoon depends on it)
import { Application } from "@hotwired/stimulus"
import "@hotwired/turbo-rails"
import "@nathanvda/cocoon"  // <-- Then cocoon (importmap will resolve to @nathanvda--cocoon.js)

// Import Chart.js for analytics pages
import Chart from 'chart.js/auto'

// Make Chart globally available
window.Chart = Chart

// Initialize Stimulus
const application = Application.start()

// Expose Stimulus globally
window.Stimulus = application

// Make jQuery globally available (some plugins expect $)
window.$ = window.jQuery = jQuery;

console.log("✅ Application loaded: jQuery, Stimulus, Turbo, Cocoon, Chart.js")

// CSRF Token handling for Turbo
document.addEventListener('turbo:load', () => {
  const csrfToken = document.querySelector('meta[name="csrf-token"]');
  if (csrfToken) {
    window.csrfToken = csrfToken.content;
    console.log('CSRF token available for Turbo:', !!window.csrfToken);
  }
});

// Ensure CSRF token is included in all Turbo requests
document.addEventListener('turbo:before-fetch-request', (event) => {
  const token = window.csrfToken || document.querySelector('meta[name="csrf-token"]')?.content;
  if (token) {
    event.detail.fetchOptions.headers['X-CSRF-Token'] = token;
  }
});

// Check if we're on a page that needs charts
document.addEventListener('DOMContentLoaded', function() {
  console.log("✅ Application.js fully loaded");
  
  const needsChart = 
    window.location.pathname.includes('analytics') ||
    window.location.pathname.includes('dashboard');
  
  if (needsChart) {
    console.log("📊 This page needs Chart.js - loaded successfully");
    console.log("Chart.js available:", typeof window.Chart !== 'undefined');
  } else {
    console.log("✅ Chart.js loaded but not needed on this page");
  }
});

// Check if jQuery and Cocoon loaded correctly
if (typeof window.$ !== 'undefined') {
  console.log("✅ jQuery loaded successfully as $");
} else {
  console.error("❌ jQuery failed to load");
}

if (typeof window.Cocoon !== 'undefined') {
  console.log("✅ Cocoon loaded successfully");
} else {
  console.warn("⚠️ Cocoon not loaded - nested forms may not work");
}

// Export for compatibility
export { application }
