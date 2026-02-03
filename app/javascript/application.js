// File: app/javascript/application.js
//
// Replace the ENTIRE file with this (copy/paste).
//
// ✅ This version is correct for an **Importmap-based Rails setup** (NOT jsbundling-rails).
// ✅ It works with layouts that use:
//      <%= javascript_importmap_tags %>
// ✅ It loads Turbo, Stimulus, and your Stimulus controllers (vehicle-catalog).
// ✅ It optionally initializes Bootstrap tooltips/popovers **IF Bootstrap is available globally**
//    (either pinned via importmap OR loaded via CDN).
// ✅ It wires CSRF headers for Turbo fetch requests.
// ✅ Includes strong debug logs so you can confirm everything is running.
//
// IMPORTANT NOTES:
// 1) This file should be SHORT in importmap apps. Do NOT paste controller code into here.
// 2) Your Stimulus controller registry must be:
//      app/javascript/controllers/application.js
//      app/javascript/controllers/index.js
//      app/javascript/controllers/vehicle_catalog_controller.js
// 3) Your importmap.rb must include:
//      pin "application", preload: true
//      pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
//      pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
//      pin_all_from "app/javascript/controllers", under: "controllers"
//
// ------------------------------------------------------------
// 1) Core Rails navigation stack (Turbo)
// ------------------------------------------------------------
import "@hotwired/turbo-rails"

// ------------------------------------------------------------
// 2) Stimulus + Controllers registry
// ------------------------------------------------------------
// This imports app/javascript/controllers/index.js which registers vehicle-catalog
import "controllers"
// ------------------------------------------------------------
// Logging / Diagnostics
// ------------------------------------------------------------
console.log("✅ app/javascript/application.js loaded (Importmap mode)")

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
  // Works if Bootstrap is available as window.bootstrap (CDN or you set it globally elsewhere)
  const bs = window.bootstrap
  if (!bs) return

  // Tooltips
  document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach((el) => {
    try {
      bs.Tooltip.getInstance(el)?.dispose()
      new bs.Tooltip(el)
    } catch (e) {
      console.warn("Tooltip init failed:", e)
    }
  })

  // Popovers
  document.querySelectorAll('[data-bs-toggle="popover"]').forEach((el) => {
    try {
      bs.Popover.getInstance(el)?.dispose()
      new bs.Popover(el)
    } catch (e) {
      console.warn("Popover init failed:", e)
    }
  })
}

function logLoadedLibraries(where = "load") {
  console.log(`✅ ${where}: diagnostics`)

  // Stimulus
  if (window.Stimulus) console.log("✅ Stimulus running")
  else console.error("❌ Stimulus not running")

  // Turbo
  if (window.Turbo) console.log("✅ Turbo available")
  else console.log("ℹ️ Turbo loaded (may not expose window.Turbo)")

  // Bootstrap (optional)
  if (window.bootstrap) console.log("✅ Bootstrap detected (window.bootstrap)")
  else console.log("ℹ️ Bootstrap not detected (window.bootstrap missing)")

  // Quick sanity check for the vehicle catalog controller
  const hasCatalog = document.querySelector('[data-controller~="vehicle-catalog"]')
  console.log("🔎 vehicle-catalog element present?", !!hasCatalog)
}

// ------------------------------------------------------------
// Events
// ------------------------------------------------------------

// On first page load (hard refresh)
document.addEventListener("DOMContentLoaded", () => {
  setGlobalCsrfToken()
  ensureBootstrapComponents()
  logLoadedLibraries("DOMContentLoaded")
})

// On Turbo navigation (soft navigation)
document.addEventListener("turbo:load", () => {
  setGlobalCsrfToken()
  ensureBootstrapComponents()
  logLoadedLibraries("turbo:load")
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

// Optional helper for manual fetch() calls
window.withCsrfHeaders = function withCsrfHeaders(headers = {}) {
  const token =
    window.csrfToken ||
    document.querySelector('meta[name="csrf-token"]')?.content ||
    setGlobalCsrfToken()

  return token ? { ...headers, "X-CSRF-Token": token } : headers
}
