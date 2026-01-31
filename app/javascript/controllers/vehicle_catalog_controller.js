// app/javascript/controllers/vehicle_catalog_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["query", "results", "make", "model", "type", "status"]

  static values = {
    url: { type: String, default: "/vehicles/catalog_search" }
  }

  connect() {
    this.timeout = null
    this.activeIndex = -1
    this.items = []
    this.hideResults()
  }

  // ====================================================
  // EVENTS
  // ====================================================
  search() {
    clearTimeout(this.timeout)

    const q = (this.queryTarget?.value || "").trim()
    if (q.length < 2) {
      this.clearResults()
      return
    }

    this.timeout = setTimeout(() => {
      this.fetchResults(q)
    }, 200)
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
    // allow click selection before clearing
    setTimeout(() => {
      this.applyManualEntryToHiddenFields()
      this.clearResults()
    }, 150)
  }

  // ====================================================
  // NETWORK
  // ====================================================
  async fetchResults(q) {
    try {
      const url = `${this.urlValue}?q=${encodeURIComponent(q)}`
      const res = await fetch(url, { headers: { Accept: "application/json" } })

      if (!res.ok) {
        this.setStatus(`Search failed (${res.status})`)
        this.clearResults()
        return
      }

      const data = await res.json()
      this.renderResults(Array.isArray(data) ? data : [])
    } catch (e) {
      this.setStatus("Catalog search error")
      this.clearResults()
    }
  }

  // ====================================================
  // RENDERING
  // ====================================================
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
    const nodes = Array.from(
      this.resultsTarget.querySelectorAll(".list-group-item")
    )

    nodes.forEach((node, idx) =>
      node.classList.toggle("active", idx === this.activeIndex)
    )

    const active = nodes[this.activeIndex]
    if (active) active.scrollIntoView({ block: "nearest" })
  }

  pickActive() {
    if (this.activeIndex < 0) return
    const item = this.items[this.activeIndex]
    if (item) this.pick(item)
  }

  // ====================================================
  // SELECTION / FIELD FILL
  // ====================================================
  pick(item) {
    if (this.hasQueryTarget) {
      this.queryTarget.value = `${item.make} ${item.model}`.trim()
    }

    if (this.hasMakeTarget)  this.makeTarget.value  = item.make  || ""
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

    // don't overwrite dropdown selection
    if (
      this.hasMakeTarget && this.makeTarget.value &&
      this.hasModelTarget && this.modelTarget.value
    ) return

    const parts = raw.split(" ", 2)
    if (this.hasMakeTarget)  this.makeTarget.value  = parts[0] || ""
    if (this.hasModelTarget) this.modelTarget.value = parts[1] || ""
  }

  // ====================================================
  // HELPERS
  // ====================================================
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
