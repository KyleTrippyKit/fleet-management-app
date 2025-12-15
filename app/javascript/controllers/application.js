// app/javascript/application.js
console.log("🚀 Application starting (Importmap)...");

// Import Turbo (from importmap)
import "@hotwired/turbo-rails";

// Import Stimulus
import { Application } from "@hotwired/stimulus";
import { definitionsFromContext } from "@hotwired/stimulus-loading";

// Start Stimulus
const application = Application.start();

// Automatically load all controllers from the `controllers` directory
const context = require.context("./controllers", true, /_controller\.js$/);
application.load(definitionsFromContext(context));

// Export for debugging
window.StimulusApplication = application;
window.Stimulus = application;

console.log("✅ Stimulus started with controllers:", 
  Array.from(application.router.modules.keys()));

// Add CSRF token to all Turbo requests
document.addEventListener("turbo:before-fetch-request", (event) => {
  const token = document.querySelector("meta[name='csrf-token']")?.content;
  if (token) {
    event.detail.fetchOptions.headers = event.detail.fetchOptions.headers || {};
    event.detail.fetchOptions.headers["X-CSRF-Token"] = token;
  }
});

console.log("✅ Application setup complete");
