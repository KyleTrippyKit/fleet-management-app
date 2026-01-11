// app/javascript/application.js

// Import Stimulus
import { Application } from "@hotwired/stimulus"
import "@hotwired/turbo-rails"

// Import Chart.js for analytics pages
import Chart from 'chart.js/auto'

// Make Chart globally available
window.Chart = Chart

// Initialize Stimulus
const application = Application.start()

// Expose Stimulus globally
window.Stimulus = application

console.log("✅ Stimulus Application started with Chart.js")

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
  console.log("✅ Application.js loaded");
  
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

// Export for compatibility
export { application }