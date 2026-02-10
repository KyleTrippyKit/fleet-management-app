```js
// File: app/javascript/application.js
//
// Replace the ENTIRE file with this (copy/paste).
//
// ✅ Importmap-based Rails setup (layout uses <%= javascript_importmap_tags %>)
// ✅ Turbo + Stimulus controllers
// ✅ Bootstrap tooltips/popovers only if window.bootstrap exists
// ✅ CSRF headers for Turbo fetch requests
// ✅ FIXED: autoHideFlashMessages now hides ONLY flash messages inside a flash container
//          (NO MORE nuking your “selected vehicle/driver” alert chips)
// ✅ Removed the “NUCLEAR OPTION” that was hiding ALL .alert elements globally
//

import "@hotwired/turbo-rails"
import "controllers"
import "polish"

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

/**
 * ✅ Only hides flash messages inside a dedicated flash container.
 * This prevents breaking UI components that also use `.alert`
 * (like your selected vehicle/driver chips).
 *
 * Supported containers:
 *  - #flash-messages
 *  - .flash-messages
 *  - [data-flash-container]
 */
function autoHideFlashMessages() {
  console.log("🔔 autoHideFlashMessages() called - hiding ONLY flash container alerts...")

  const flashContainers = [
    document.getElementById("flash-messages"),
    document.querySelector(".flash-messages"),
    document.querySelector("[data-flash-container]"),
  ].filter(Boolean)

  if (flashContainers.length === 0) {
    console.log("ℹ️ No flash container found (#flash-messages / .flash-messages / [data-flash-container]). Skipping.")
    return
  }

  const flashMessages = []
  flashContainers.forEach((container) => {
    container.querySelectorAll(".alert, .alert-dismissible, [role='alert']").forEach((el) => {
      flashMessages.push(el)
    })
  })

  console.log(`🎯 Flash messages found inside container(s): ${flashMessages.length}`)

  flashMessages.forEach((flash, index) => {
    setTimeout(() => {
      // Bootstrap dismiss if possible
      if (window.bootstrap && flash.classList.contains("alert-dismissible")) {
        try {
          const bsAlert = window.bootstrap.Alert.getOrCreateInstance(flash)
          bsAlert.close()
          console.log(`✅ Closed flash ${index + 1} via Bootstrap`)
          return
        } catch (e) {
          console.warn("Bootstrap dismiss failed:", e)
        }
      }

      // Manual fade + remove
      flash.style.transition = "all 0.5s ease-out"
      flash.style.opacity = "0"
      flash.style.maxHeight = "0"
      flash.style.paddingTop = "0"
      flash.style.paddingBottom = "0"
      flash.style.marginTop = "0"
      flash.style.marginBottom = "0"
      flash.style.borderWidth = "0"
      flash.style.overflow = "hidden"

      setTimeout(() => {
        flash.remove()
        console.log(`✅ Removed flash ${index + 1}`)
      }, 550)
    }, 2000)
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

  // Sanity check for any Stimulus controllers present
  const anyController = document.querySelector("[data-controller]")
  console.log("🔎 any data-controller element present?", !!anyController)
}

// ------------------------------------------------------------
// Events
// ------------------------------------------------------------

// Hard refresh
document.addEventListener("DOMContentLoaded", () => {
  console.log("📄 DOMContentLoaded event fired")
  setGlobalCsrfToken()
  ensureBootstrapComponents()
  autoHideFlashMessages()
  logLoadedLibraries("DOMContentLoaded")
})

// Turbo navigation
document.addEventListener("turbo:load", () => {
  console.log("🌀 turbo:load event fired")
  setGlobalCsrfToken()
  ensureBootstrapComponents()
  autoHideFlashMessages()
  logLoadedLibraries("turbo:load")
})

// Ensure Turbo fetch requests include CSRF header
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

// Expose flash helper globally
window.autoHideFlashMessages = autoHideFlashMessages
```
