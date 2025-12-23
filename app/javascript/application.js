// app/javascript/application.js

// Import Stimulus
import { Application } from "@hotwired/stimulus"

// Initialize Stimulus
const application = Application.start()

// Expose Stimulus globally
window.Stimulus = application

console.log("✅ Stimulus Application started")

// Check if we're on a page that needs Chart.js
document.addEventListener('DOMContentLoaded', function() {
  console.log("✅ Application.js loaded");
  
  const needsChart = 
    window.location.pathname.includes('analytics') ||
    window.location.pathname.includes('dashboard');
  
  if (needsChart) {
    console.log("📊 This page needs Chart.js");
  } else {
    console.log("✅ Gantt page - Chart.js not needed");
  }
});

// Export for compatibility
export { application }