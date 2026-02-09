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
import "polish"
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

function autoHideFlashMessages() {
  console.log("🔔 autoHideFlashMessages() called - looking for flash messages...");
  
  // BROAD SELECTORS TO CATCH ALL FLASH MESSAGES
  const selectors = [
    '.alert', 
    '.alert-dismissible',
    '[role="alert"]',
    '.flash-message',
    '.alert-info',
    '.alert-success',
    '.alert-warning',
    '.alert-danger',
    '#flash-messages > *', // Direct children of flash-messages container
    '.container.mt-3 > .alert' // Alerts in container mt-3 (your layout)
  ];
  
  // Try each selector
  let flashMessages = [];
  selectors.forEach(selector => {
    const found = document.querySelectorAll(selector);
    if (found.length > 0) {
      console.log(`🔍 Found ${found.length} with selector: ${selector}`);
      found.forEach(el => {
        // Avoid duplicates
        if (!flashMessages.includes(el)) {
          flashMessages.push(el);
        }
      });
    }
  });
  
  console.log(`🎯 Total unique flash messages found: ${flashMessages.length}`);
  
  if (flashMessages.length === 0) {
    // Fallback: look for any element with flash-like text
    console.log("⚠️ No flash messages found with selectors, trying text search...");
    const allElements = document.querySelectorAll('*');
    allElements.forEach(el => {
      const text = el.textContent?.toLowerCase() || '';
      if (text.includes('signed in') || text.includes('successfully') || text.includes('welcome')) {
        console.log(`   Found flash-like text: ${text.substring(0, 50)}...`);
        if (!flashMessages.includes(el)) {
          flashMessages.push(el);
        }
      }
    });
  }
  
  // Process each flash message
  flashMessages.forEach(function(flash, index) {
    console.log(`   Processing flash ${index + 1}: ${flash.className || flash.tagName}`);
    
    // Set a timeout to hide after 2 seconds
    setTimeout(function() {
      console.log(`⏰ Hiding flash ${index + 1} after 2 seconds`);
      
      // Try Bootstrap method first
      if (window.bootstrap && flash.classList && flash.classList.contains('alert-dismissible')) {
        try {
          const bsAlert = window.bootstrap.Alert.getOrCreateInstance(flash);
          bsAlert.close();
          console.log(`   ✅ Used Bootstrap dismiss method`);
          return;
        } catch (e) {
          console.log(`   ❌ Bootstrap dismiss failed: ${e.message}`);
        }
      }
      
      // Fallback: manual fade out
      fadeOutFlash(flash);
      
    }, 2000); // 2 seconds
  });
  
  function fadeOutFlash(flashElement) {
    console.log(`   Using manual fade out`);
    
    // Add transition for smooth fade
    flashElement.style.transition = 'all 0.5s ease-out';
    flashElement.style.opacity = '0';
    flashElement.style.maxHeight = '0';
    flashElement.style.paddingTop = '0';
    flashElement.style.paddingBottom = '0';
    flashElement.style.marginTop = '0';
    flashElement.style.marginBottom = '0';
    flashElement.style.borderWidth = '0';
    flashElement.style.overflow = 'hidden';
    
    // Remove from DOM after animation
    setTimeout(() => {
      if (flashElement.parentNode) {
        flashElement.parentNode.removeChild(flashElement);
        console.log(`   ✅ Removed from DOM`);
      } else {
        console.log(`   ℹ️ Already removed or no parent`);
      }
    }, 500); // Wait for fade animation to complete
  }
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
  console.log("📄 DOMContentLoaded event fired");
  setGlobalCsrfToken()
  ensureBootstrapComponents()
  autoHideFlashMessages()
  logLoadedLibraries("DOMContentLoaded")
})

// On Turbo navigation (soft navigation)
document.addEventListener("turbo:load", () => {
  console.log("🌀 turbo:load event fired");
  setGlobalCsrfToken()
  ensureBootstrapComponents()
  autoHideFlashMessages()
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

// Make the function available globally if needed
window.autoHideFlashMessages = autoHideFlashMessages;

// NUCLEAR OPTION: Fallback timer just in case
setTimeout(() => {
  console.log("💣 Fallback: Checking for remaining flash messages...");
  
  // Look for any remaining alerts and force hide them
  const remainingAlerts = document.querySelectorAll('.alert, .alert-dismissible, [role="alert"]');
  if (remainingAlerts.length > 0) {
    console.log(`💥 Force hiding ${remainingAlerts.length} remaining alerts`);
    remainingAlerts.forEach(alert => {
      alert.style.display = 'none';
      alert.style.visibility = 'hidden';
      alert.style.opacity = '0';
      alert.style.height = '0';
      alert.style.padding = '0';
      alert.style.margin = '0';
      alert.style.overflow = 'hidden';
      alert.style.border = '0';
    });
  }
}, 3000); // 3 seconds as fallback