// File: app/javascript/application.js
//
// Replace the ENTIRE file with this (copy/paste).
//
// ✅ This version is correct for a JS-bundled Rails setup (jsbundling-rails).
// ✅ It loads Turbo, Stimulus, your Stimulus controllers (vehicle-catalog), Bootstrap, jQuery, Cocoon,
//    and Chartkick/Chart.js in a clean order.
// ✅ It also handles CSRF headers for Turbo fetch requests and re-initializes Bootstrap tooltips/popovers
//    on Turbo navigation.
//
// IMPORTANT NOTES:
// 1) This assumes your layout uses:
//      <%= javascript_include_tag "application", "data-turbo-track": "reload", defer: true %>
//    and does NOT use <%= javascript_importmap_tags %>.
// 2) Your Stimulus controller files must live under:
//      app/javascript/controllers/
//    with an index.js that registers them.
//
// ------------------------------------------------------------
// 1) Core Rails navigation stack (Turbo)
// ------------------------------------------------------------
import "@hotwired/turbo-rails"

// ------------------------------------------------------------
// 2) jQuery (must be imported BEFORE Cocoon)
// ------------------------------------------------------------
import $ from "jquery"
window.$ = $
window.jQuery = $

// ------------------------------------------------------------
// 3) Bootstrap (JS)
// ------------------------------------------------------------
// Use namespace import so we can call bootstrap.Tooltip / bootstrap.Popover etc.
import * as bootstrap from "bootstrap"
window.bootstrap = bootstrap

// ------------------------------------------------------------
// 4) Cocoon (depends on jQuery)
// ------------------------------------------------------------
import "@nathanvda/cocoon"

// ------------------------------------------------------------
// 5) Charts
// ------------------------------------------------------------
// Chartkick will auto-detect Chart.js when both are present.
// (Depending on versions, Chartkick may require Chart.js to be loaded first.)
import "chart.js"
import "chartkick"

// ------------------------------------------------------------
// 6) Stimulus + Controllers registry
// ------------------------------------------------------------
import { Application } from "@hotwired/stimulus"

// This should import app/javascript/controllers/index.js
// which registers controllers like vehicle-catalog, etc.
import "controllers"

// Start Stimulus
const application = Application.start()
window.Stimulus = application

// ------------------------------------------------------------
// Logging / Diagnostics
// ------------------------------------------------------------
console.log("✅ application.js loaded (Turbo + Stimulus + Bootstrap + jQuery + Cocoon + Chartkick)")

// ------------------------------------------------------------
// Helpers
// ------------------------------------------------------------
function setGlobalCsrfToken() {
  const meta = document.querySelector('meta[name="csrf-token"]')
  if (meta?.content) {
    window.csrfToken = meta.content
    return meta.content
  }
  return null
}

function ensureBootstrapComponents() {
  // Tooltips
  const tooltipTriggerList = document.querySelectorAll('[data-bs-toggle="tooltip"]')
  tooltipTriggerList.forEach((el) => {
    try {
      // Avoid double-init: dispose existing instance first (if any)
      bootstrap.Tooltip.getInstance(el)?.dispose()
      new bootstrap.Tooltip(el)
    } catch (e) {
      console.warn("Tooltip init failed:", e)
    }
  })

  // Popovers
  const popoverTriggerList = document.querySelectorAll('[data-bs-toggle="popover"]')
  popoverTriggerList.forEach((el) => {
    try {
      bootstrap.Popover.getInstance(el)?.dispose()
      new bootstrap.Popover(el)
    } catch (e) {
      console.warn("Popover init failed:", e)
    }
  })
}

function logLoadedLibraries() {
  console.log("✅ DOM loaded")

  // Bootstrap
  if (typeof window.bootstrap !== "undefined") {
    console.log("✅ Bootstrap loaded successfully")
  } else {
    console.error("❌ Bootstrap not loaded")
  }

  // jQuery
  if (typeof window.$ !== "undefined") {
    console.log("✅ jQuery loaded successfully")
  } else {
    console.error("❌ jQuery failed to load")
  }

  // Chartkick
  if (typeof window.Chartkick !== "undefined") {
    console.log("✅ Chartkick loaded successfully")
  } else {
    console.error("❌ Chartkick not loaded")
  }

  // Chart.js
  // (Depending on Chart.js version / bundling, it may or may not expose global `Chart`.)
  if (typeof window.Chart !== "undefined") {
    console.log("✅ Chart.js global Chart is available")
  } else {
    console.log("ℹ️ Chart.js loaded (may not expose global Chart in ESM mode)")
  }

  // Stimulus
  if (typeof window.Stimulus !== "undefined") {
    console.log("✅ Stimulus running")
  } else {
    console.error("❌ Stimulus not running")
  }

  // Turbo
  if (typeof window.Turbo !== "undefined") {
    console.log("✅ Turbo available")
  } else {
    console.log("ℹ️ Turbo is loaded (may not expose window.Turbo in some builds)")
  }
}

// ------------------------------------------------------------
// Events
// ------------------------------------------------------------

// On first page load (hard refresh)
document.addEventListener("DOMContentLoaded", () => {
  setGlobalCsrfToken()
  ensureBootstrapComponents()
  logLoadedLibraries()
})

// On Turbo navigation (soft navigation)
document.addEventListener("turbo:load", () => {
  setGlobalCsrfToken()
  ensureBootstrapComponents()

  // Helpful log during debugging:
  console.log("✅ turbo:load - reinitialized bootstrap + refreshed CSRF")
})

// Ensure Turbo fetch requests include CSRF header (important for POST/PUT/PATCH/DELETE)
document.addEventListener("turbo:before-fetch-request", (event) => {
  const token =
    window.csrfToken ||
    document.querySelector('meta[name="csrf-token"]')?.content ||
    setGlobalCsrfToken()

  if (token) {
    event.detail.fetchOptions.headers["X-CSRF-Token"] = token
  }
})

// Optional: If your app uses custom fetch() calls frequently, you can wrap a helper here.
// (Not required for your vehicle catalog search because you already pass Accept header.)
window.withCsrfHeaders = function withCsrfHeaders(headers = {}) {
  const token =
    window.csrfToken ||
    document.querySelector('meta[name="csrf-token"]')?.content ||
    setGlobalCsrfToken()

  return token ? { ...headers, "X-CSRF-Token": token } : headers
}

// Export Stimulus application if you need it elsewhere (rare, but sometimes useful)
export { application }
