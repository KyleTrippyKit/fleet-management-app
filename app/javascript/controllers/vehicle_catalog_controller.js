// File: app/javascript/controllers/vehicle_catalog_controller.js
// Replace the ENTIRE file with this (copy/paste).

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["query", "results", "make", "model", "type", "status"]
  static values = { url: { type: String, default: "/vehicles/catalog_search" } }

  connect() {
    this.timeout = null
    this.activeIndex = -1
    this.items = []
    this.hideResults()
    console.log("✅ vehicle-catalog connected", { url: this.urlValue })
  }

  // -------------------------
  // Events
  // -------------------------
  search() {
    clearTimeout(this.timeout)

    const q = (this.queryTarget?.value || "").trim()
    if (q.length < 2) {
      this.clearResults()
      return
    }

    this.timeout = setTimeout(() => this.fetchResults(q), 150)
  }

  keydown(event) {
    if (this.isHidden()) return
    if (!this.items.length) return

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.moveActive(1)
        break
      case "ArrowUp":
        event.preventDefault()
        this.moveActive(-1)
        break
      case "Enter":
        event.preventDefault()
        this.pickActive()
        break
      case "Escape":
        event.preventDefault()
        this.clearResults()
        break
    }
  }

  blur() {
    // Let click selection happen first
    setTimeout(() => {
      this.applyManualEntryToHiddenFields()
      this.clearResults()
    }, 150)
  }

  // -------------------------
  // Network
  // -------------------------
  async fetchResults(q) {
    try {
      const url = `${this.urlValue}?q=${encodeURIComponent(q)}`
      console.log("🔎 fetching:", url)

      const res = await fetch(url, { headers: { Accept: "application/json" } })
      if (!res.ok) {
        this.setStatus(`Search failed (${res.status})`)
        this.clearResults()
        return
      }

      const data = await res.json()
      this.renderResults(Array.isArray(data) ? data : [])

      if (!data || data.length === 0) {
        this.setStatus("No match found — you can still type manually (e.g. Toyota Hilux).")
      } else {
        this.setStatus("")
      }
    } catch (e) {
      console.error("❌ catalog fetch error:", e)
      this.setStatus("Catalog search error")
      this.clearResults()
    }
  }

  // -------------------------
  // Rendering
  // -------------------------
  renderResults(items) {
    this.items = items || []
    this.activeIndex = -1

    if (!this.items.length) {
      this.clearResults()
      return
    }

    this.resultsTarget.innerHTML = ""

    this.items.forEach((item, index) => {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className = "list-group-item list-group-item-action"
      btn.dataset.index = String(index)

      btn.textContent = item.vehicle_type
        ? `${item.label} • ${item.vehicle_type}`
        : item.label

      // use mousedown so blur doesn't fire first
      btn.addEventListener("mousedown", (e) => {
        e.preventDefault()
        this.pick(item)
      })

      this.resultsTarget.appendChild(btn)
    })

    this.showResults()
  }

  moveActive(delta) {
    const max = this.items.length - 1
    let next = this.activeIndex + delta
    if (next < 0) next = max
    if (next > max) next = 0
    this.activeIndex = next
    this.highlightActive()
  }

  highlightActive() {
    const nodes = Array.from(this.resultsTarget.querySelectorAll(".list-group-item"))
    nodes.forEach((node, idx) => node.classList.toggle("active", idx === this.activeIndex))
    nodes[this.activeIndex]?.scrollIntoView({ block: "nearest" })
  }

  pickActive() {
    if (this.activeIndex < 0) return
    const item = this.items[this.activeIndex]
    if (item) this.pick(item)
  }

  // -------------------------
  // Selection / Field fill
  // -------------------------
  pick(item) {
    if (this.hasQueryTarget) {
      this.queryTarget.value = `${item.make} ${item.model}`.trim()
    }

    if (this.hasMakeTarget) this.makeTarget.value = item.make || ""
    if (this.hasModelTarget) this.modelTarget.value = item.model || ""

    if (this.hasTypeTarget && item.vehicle_type && !this.typeTarget.value) {
      this.typeTarget.value = item.vehicle_type
    }

    this.setStatus("")
    this.clearResults()
  }

  applyManualEntryToHiddenFields() {
    if (!this.hasQueryTarget) return

    const raw = (this.queryTarget.value || "").trim().replace(/\s+/g, " ")
    if (!raw) return

    // Always try to populate make/model from what user typed.
    // If only one word provided, we still populate model with "Unknown" via server logic,
    // but we keep model blank here (server will fix safely).
    const parts = raw.split(" ", 2)
    const makePart = (parts[0] || "").trim()
    const modelPart = (parts[1] || "").trim()

    if (this.hasMakeTarget) this.makeTarget.value = makePart
    if (this.hasModelTarget) this.modelTarget.value = modelPart
  }

  // -------------------------
  // Helpers
  // -------------------------
  clearResults() {
    this.items = []
    this.activeIndex = -1
    if (this.hasResultsTarget) this.resultsTarget.innerHTML = ""
    this.hideResults()
  }

  showResults() {
    if (this.hasResultsTarget) this.resultsTarget.style.display = "block"
  }

  hideResults() {
    if (this.hasResultsTarget) this.resultsTarget.style.display = "none"
  }

  isHidden() {
    return !this.hasResultsTarget || this.resultsTarget.style.display === "none"
  }

  setStatus(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message || ""
  }
}
