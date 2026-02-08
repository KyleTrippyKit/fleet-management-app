import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { text: String }

  start(event) {
    const btn = event.currentTarget
    if (!btn || btn.classList.contains("is-loading")) return

    btn.classList.add("is-loading")

    // Optional: change button text
    const text = this.textValue
    if (text) {
      btn.dataset.originalText = btn.innerHTML
      btn.innerHTML = `${text} <span class="spinner-border spinner-border-sm btn-spinner" role="status" aria-hidden="true"></span>`
      return
    }

    // Default: just append spinner if missing
    if (!btn.querySelector(".btn-spinner")) {
      const spinner = document.createElement("span")
      spinner.className = "spinner-border spinner-border-sm btn-spinner"
      spinner.setAttribute("role", "status")
      spinner.setAttribute("aria-hidden", "true")
      btn.appendChild(spinner)
    }
  }

  stop() {
    const btn = this.element
    btn.classList.remove("is-loading")
    if (btn.dataset.originalText) btn.innerHTML = btn.dataset.originalText
  }
}
