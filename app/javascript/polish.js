// app/javascript/polish.js
// Polish kit: loading states, feedback, Turbo-safe interactions

import { Controller } from "@hotwired/stimulus"
import { application } from "./controllers/application" // ✅ IMPORTANT: NOT "./controllers"

// -------------------------------
// Loading state controller
// -------------------------------
export class LoadingController extends Controller {
  static targets = ["button", "form"]

  connect() {
    if (this.hasFormTarget) {
      this.formTarget.addEventListener("submit", this.handleSubmit.bind(this))
    }
  }

  handleSubmit(event) {
    const form = event.target
    const submitButton = form.querySelector('[type="submit"]')

    if (submitButton && !form.dataset.turboStream) {
      this.showLoading(submitButton)

      form.addEventListener(
        "turbo:submit-end",
        () => this.hideLoading(submitButton),
        { once: true }
      )

      setTimeout(() => this.hideLoading(submitButton), 5000)
    }
  }

  showLoading(button) {
    button.classList.add("btn-loading")
    button.disabled = true
    button.setAttribute("aria-busy", "true")

    button.dataset.originalText = button.innerHTML
  }

  hideLoading(button) {
    button.classList.remove("btn-loading")
    button.disabled = false
    button.removeAttribute("aria-busy")

    if (button.dataset.originalText) {
      button.innerHTML = button.dataset.originalText
      delete button.dataset.originalText
    }
  }

  show(event) {
    const button = event.currentTarget
    this.showLoading(button)
    setTimeout(() => this.hideLoading(button), 3000)
  }
}

// -------------------------------
// Success feedback controller
// -------------------------------
export class FeedbackController extends Controller {
  showSuccess(event) {
    const button = event.currentTarget
    button.classList.add("btn-success")
    setTimeout(() => button.classList.remove("btn-success"), 300)
  }
}

// -------------------------------
// Form validation controller
// -------------------------------
export class FormController extends Controller {
  static targets = ["input", "error"]

  connect() {
    this.inputTargets.forEach((input) => {
      input.addEventListener("blur", this.validateInput.bind(this))
    })
  }

  validateInput(event) {
    const input = event.target
    const isValid = input.checkValidity()

    if (input.value.trim() === "") return

    if (isValid) {
      input.classList.remove("is-invalid")
      input.classList.add("is-valid")
    } else {
      input.classList.remove("is-valid")
      input.classList.add("is-invalid")
    }
  }
}

// ✅ SAFE registration (prevents duplicate registration errors)
function safeRegister(identifier, controller) {
  try {
    application.register(identifier, controller)
  } catch (e) {
    // If already registered, ignore quietly
    if (!String(e?.message || "").includes("already been registered")) {
      console.warn(`Stimulus register failed for ${identifier}:`, e)
    }
  }
}

safeRegister("loading", LoadingController)
safeRegister("feedback", FeedbackController)
safeRegister("form", FormController)

// -------------------------------
// Turbo-safe interactions
// -------------------------------
document.addEventListener("turbo:load", () => {
  // Focus first input in modals when shown
  document.querySelectorAll(".modal").forEach((modal) => {
    modal.addEventListener("shown.bs.modal", () => {
      const firstInput = modal.querySelector("input, select, textarea")
      if (firstInput) firstInput.focus()
    })
  })

  // Smooth scroll to top on navigation
  window.scrollTo({ top: 0, behavior: "smooth" })
})

// -------------------------------
// Global keyboard shortcuts
// -------------------------------
document.addEventListener("keydown", (event) => {
  // Ctrl/Cmd + K to focus search
  if ((event.ctrlKey || event.metaKey) && event.key === "k") {
    event.preventDefault()
    const searchInput = document.querySelector(
      'input[type="search"], input[name="query"]'
    )
    if (searchInput) {
      searchInput.focus()
      searchInput.select()
    }
  }

  // Escape to close modals
  if (event.key === "Escape") {
    const openModal = document.querySelector(".modal.show")
    if (openModal && window.bootstrap) {
      const modal = window.bootstrap.Modal.getInstance(openModal)
      if (modal) modal.hide()
    }
  }
})

// -------------------------------
// Empty state helper
// -------------------------------
window.showEmptyState = (container, message = "No data found", icon = "bi-inbox") => {
  container.innerHTML = `
    <div class="empty-state">
      <div class="empty-state-icon">
        <i class="bi ${icon}"></i>
      </div>
      <h4 class="text-muted mb-3">${message}</h4>
      <p class="text-muted">Try adjusting your filters or adding new data.</p>
    </div>
  `
}
