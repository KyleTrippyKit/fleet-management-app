// app/javascript/controllers/alert_search_controller.js
import { Controller } from "@hotwired/stimulus"

// Robust search-select controller for Alerts New/Edit form
// Fixes: "finds results but doesn't select when I click"
// Root cause: click happens after input blur; results hide before click fires.
// Solution: use mousedown to select before blur.

export default class extends Controller {
  static targets = [
    // Vehicle
    "vehicleInput",
    "vehicleHidden",
    "vehicleResults",
    "vehicleList",
    "vehicleSelected",
    "vehicleSelectedText",

    // Driver
    "driverInput",
    "driverHidden",
    "driverResults",
    "driverList",
    "driverSelected",
    "driverSelectedText"
  ]

  connect() {
    this.vehicleAbort = null
    this.driverAbort = null

    this.vehicleDebounce = null
    this.driverDebounce = null

    // close dropdown when clicking outside controller
    this._outsideHandler = (e) => {
      if (!this.element.contains(e.target)) {
        this.hideVehicleResults()
        this.hideDriverResults()
      }
    }
    document.addEventListener("mousedown", this._outsideHandler)

    // If edit page already has hidden IDs, show chips
    this.restoreExistingSelections()
  }

  disconnect() {
    document.removeEventListener("mousedown", this._outsideHandler)
    this.abortVehicle()
    this.abortDriver()
  }

  // -------------------------
  // VEHICLE SEARCH
  // -------------------------
  vehicleInput() {
    const term = (this.vehicleInputTarget.value || "").trim()

    // If user deletes text, don't auto-clear hidden selection (they may be editing description etc.)
    // Only clear when they explicitly press the X button.
    if (term.length < 2) {
      this.hideVehicleResults()
      return
    }

    clearTimeout(this.vehicleDebounce)
    this.vehicleDebounce = setTimeout(() => this.fetchVehicles(term), 200)
  }

  async fetchVehicles(term) {
    const url = this.vehicleInputTarget.dataset.searchUrl
    if (!url) return

    this.abortVehicle()
    this.vehicleAbort = new AbortController()

    const qs = new URLSearchParams({ q: term }).toString()
    const fullUrl = `${url}${url.includes("?") ? "&" : "?"}${qs}`

    try {
      const res = await fetch(fullUrl, {
        headers: { Accept: "application/json" },
        signal: this.vehicleAbort.signal
      })
      if (!res.ok) throw new Error(`Vehicle search failed (${res.status})`)
      const data = await res.json()

      this.renderVehicleResults(Array.isArray(data) ? data : [])
    } catch (e) {
      if (e.name === "AbortError") return
      console.warn("Vehicle search error:", e)
      this.renderVehicleResults([])
    }
  }

  renderVehicleResults(items) {
    if (!this.hasVehicleListTarget) return

    this.vehicleListTarget.innerHTML = ""

    if (!items.length) {
      this.hideVehicleResults()
      return
    }

    items.forEach((item) => {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className = "list-group-item list-group-item-action search-result-item"
      btn.textContent = item.label || `Vehicle #${item.id}`

      // ✅ critical: mousedown happens before blur
      btn.addEventListener("mousedown", (ev) => {
        ev.preventDefault()
        ev.stopPropagation()
        this.selectVehicle(item)
      })

      this.vehicleListTarget.appendChild(btn)
    })

    this.showVehicleResults()
  }

  selectVehicle(item) {
    if (this.hasVehicleHiddenTarget) {
      this.vehicleHiddenTarget.value = item.id
      this.vehicleHiddenTarget.dispatchEvent(new Event("change", { bubbles: true }))
    }

    if (this.hasVehicleSelectedTextTarget) {
      this.vehicleSelectedTextTarget.textContent = item.label || `Vehicle #${item.id}`
    }

    // show chip + hide results
    if (this.hasVehicleSelectedTarget) this.vehicleSelectedTarget.style.display = "block"
    this.hideVehicleResults()

    // Optionally keep input readable but not required
    if (this.hasVehicleInputTarget) {
      this.vehicleInputTarget.value = ""
      this.vehicleInputTarget.blur()
    }
  }

  clearVehicle(ev) {
    ev?.preventDefault()
    if (this.hasVehicleHiddenTarget) this.vehicleHiddenTarget.value = ""
    if (this.hasVehicleSelectedTarget) this.vehicleSelectedTarget.style.display = "none"
    this.hideVehicleResults()
  }

  showVehicleResults() {
    if (this.hasVehicleResultsTarget) this.vehicleResultsTarget.style.display = "block"
  }

  hideVehicleResults() {
    if (this.hasVehicleResultsTarget) this.vehicleResultsTarget.style.display = "none"
  }

  abortVehicle() {
    if (this.vehicleAbort) {
      try { this.vehicleAbort.abort() } catch (_) {}
      this.vehicleAbort = null
    }
  }

  // -------------------------
  // DRIVER SEARCH
  // -------------------------
  driverInput() {
    const term = (this.driverInputTarget.value || "").trim()

    if (term.length < 2) {
      this.hideDriverResults()
      return
    }

    clearTimeout(this.driverDebounce)
    this.driverDebounce = setTimeout(() => this.fetchDrivers(term), 200)
  }

  async fetchDrivers(term) {
    const url = this.driverInputTarget.dataset.searchUrl
    if (!url) return

    this.abortDriver()
    this.driverAbort = new AbortController()

    const qs = new URLSearchParams({ q: term }).toString()
    const fullUrl = `${url}${url.includes("?") ? "&" : "?"}${qs}`

    try {
      const res = await fetch(fullUrl, {
        headers: { Accept: "application/json" },
        signal: this.driverAbort.signal
      })
      if (!res.ok) throw new Error(`Driver search failed (${res.status})`)
      const data = await res.json()

      this.renderDriverResults(Array.isArray(data) ? data : [])
    } catch (e) {
      if (e.name === "AbortError") return
      console.warn("Driver search error:", e)
      this.renderDriverResults([])
    }
  }

  renderDriverResults(items) {
    if (!this.hasDriverListTarget) return

    this.driverListTarget.innerHTML = ""

    if (!items.length) {
      this.hideDriverResults()
      return
    }

    items.forEach((item) => {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className = "list-group-item list-group-item-action search-result-item"
      btn.textContent = item.label || `Driver #${item.id}`

      // ✅ critical: mousedown happens before blur
      btn.addEventListener("mousedown", (ev) => {
        ev.preventDefault()
        ev.stopPropagation()
        this.selectDriver(item)
      })

      this.driverListTarget.appendChild(btn)
    })

    this.showDriverResults()
  }

  selectDriver(item) {
    if (this.hasDriverHiddenTarget) {
      this.driverHiddenTarget.value = item.id
      this.driverHiddenTarget.dispatchEvent(new Event("change", { bubbles: true }))
    }

    if (this.hasDriverSelectedTextTarget) {
      this.driverSelectedTextTarget.textContent = item.label || `Driver #${item.id}`
    }

    if (this.hasDriverSelectedTarget) this.driverSelectedTarget.style.display = "block"
    this.hideDriverResults()

    if (this.hasDriverInputTarget) {
      this.driverInputTarget.value = ""
      this.driverInputTarget.blur()
    }
  }

  clearDriver(ev) {
    ev?.preventDefault()
    if (this.hasDriverHiddenTarget) this.driverHiddenTarget.value = ""
    if (this.hasDriverSelectedTarget) this.driverSelectedTarget.style.display = "none"
    this.hideDriverResults()
  }

  showDriverResults() {
    if (this.hasDriverResultsTarget) this.driverResultsTarget.style.display = "block"
  }

  hideDriverResults() {
    if (this.hasDriverResultsTarget) this.driverResultsTarget.style.display = "none"
  }

  abortDriver() {
    if (this.driverAbort) {
      try { this.driverAbort.abort() } catch (_) {}
      this.driverAbort = null
    }
  }

  // -------------------------
  // Restore existing values (edit page)
  // -------------------------
  restoreExistingSelections() {
    // Vehicle
    if (this.hasVehicleHiddenTarget && this.vehicleHiddenTarget.value) {
      if (this.hasVehicleSelectedTarget) this.vehicleSelectedTarget.style.display = "block"
      if (this.hasVehicleSelectedTextTarget) {
        this.vehicleSelectedTextTarget.textContent = `Selected Vehicle ID: ${this.vehicleHiddenTarget.value}`
      }
    } else {
      if (this.hasVehicleSelectedTarget) this.vehicleSelectedTarget.style.display = "none"
    }

    // Driver
    if (this.hasDriverHiddenTarget && this.driverHiddenTarget.value) {
      if (this.hasDriverSelectedTarget) this.driverSelectedTarget.style.display = "block"
      if (this.hasDriverSelectedTextTarget) {
        this.driverSelectedTextTarget.textContent = `Selected Driver ID: ${this.driverHiddenTarget.value}`
      }
    } else {
      if (this.hasDriverSelectedTarget) this.driverSelectedTarget.style.display = "none"
    }
  }
}
