// File: app/javascript/application.js
//
// PRODUCTION SAFE VERSION
// ✅ Turbo
// ✅ Stimulus controllers
// ✅ Polish kit restored
// ✅ Bootstrap tooltips
// ✅ CSRF headers
// ✅ Flash auto-hide (container-scoped only)
//

import "@hotwired/turbo-rails"
import "controllers"
import "polish"
import "channels"

console.log("✅ app/javascript/application.js loaded (PRODUCTION MODE)")

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

  document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach((el) => {
    try {
      bs.Tooltip.getInstance(el)?.dispose()
      new bs.Tooltip(el)
    } catch (_) {}
  })

  document.querySelectorAll('[data-bs-toggle="popover"]').forEach((el) => {
    try {
      bs.Popover.getInstance(el)?.dispose()
      new bs.Popover(el)
    } catch (_) {}
  })
}

/**
 * SAFE flash auto-hide
 * Only hides alerts inside #flash-messages
 */
function autoHideFlashMessages() {
  const container = document.getElementById("flash-messages")
  if (!container) return

  const alerts = container.querySelectorAll(".alert, .alert-dismissible, [role='alert']")
  if (!alerts.length) return

  alerts.forEach((flash) => {
    setTimeout(() => {
      flash.style.transition = "all 0.4s ease"
      flash.style.opacity = "0"
      flash.style.maxHeight = "0"
      flash.style.overflow = "hidden"

      setTimeout(() => {
        try { flash.remove() } catch (_) {}
      }, 450)
    }, 2000)
  })
}

document.addEventListener("DOMContentLoaded", () => {
  setGlobalCsrfToken()
  ensureBootstrapComponents()
  autoHideFlashMessages()
})

document.addEventListener("turbo:load", () => {
  setGlobalCsrfToken()
  ensureBootstrapComponents()
  autoHideFlashMessages()
})

document.addEventListener("turbo:before-fetch-request", (event) => {
  const token =
    window.csrfToken ||
    document.querySelector('meta[name="csrf-token"]')?.content

  if (token) {
    event.detail.fetchOptions.headers["X-CSRF-Token"] = token
  }
})
