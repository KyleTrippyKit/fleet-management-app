// app/javascript/application.js
import "@hotwired/turbo-rails"
import "./controllers"

console.log("✅ Application.js loaded")

// Turbo error handling
document.addEventListener("turbo:click", (event) => {
  console.log("🔗 Turbo click:", event.target?.tagName)
})

document.addEventListener("turbo:before-visit", (event) => {
  console.log("🚀 Turbo before visit:", event.detail.url)
})

document.addEventListener("turbo:visit", (event) => {
  console.log("📍 Turbo visit:", event.detail.url)
})

document.addEventListener("turbo:load", () => {
  console.log("✅ Turbo loaded")
  // Force Bootstrap re-initialization for dropdowns
  if (typeof bootstrap !== 'undefined') {
    document.querySelectorAll('[data-bs-toggle="dropdown"]').forEach(dropdown => {
      new bootstrap.Dropdown(dropdown)
    })
  }
})

document.addEventListener("turbo:before-fetch-request", (event) => {
  console.log("📡 Fetching:", event.detail.url)
})

document.addEventListener("turbo:before-fetch-response", (event) => {
  console.log("📥 Response received")
})

document.addEventListener("turbo:render", () => {
  console.log("🎨 Turbo rendered")
})

document.addEventListener("turbo:before-cache", () => {
  console.log("💾 Turbo caching page")
})

// Handle Turbo errors
document.addEventListener("turbo:error", (event) => {
  console.error("❌ Turbo error:", event.detail)
  // On error, force a full page reload
  window.location.reload()
})

// Handle missing or blank content
let lastContentCheck = Date.now()
setInterval(() => {
  // Check if body has content
  if (document.body && document.body.innerHTML.trim() === '' || document.body.children.length === 0) {
    console.warn("⚠️ Page appears blank - reloading")
    window.location.reload()
  }
}, 3000)

// Log when page is fully loaded
window.addEventListener("load", () => {
  console.log("✅ Full page load complete")
  console.log("📄 Page has", document.body.children.length, "children")
})