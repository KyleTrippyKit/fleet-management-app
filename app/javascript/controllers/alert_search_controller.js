// File: app/javascript/controllers/alert_search_controller.js
import { Controller } from "@hotwired/stimulus"

// Robust search-select controller for Alerts New/Edit form
// Fixes: "finds results but doesn't select when I click"
// Root cause: blur hides results before click fires.
// Solution: select on POINTERDOWN/MOUSEDOWN (before blur), and never hide on input blur.
// Also supports keyboard selection + proper restore on edit.

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

    // keyboard highlight index
    this.vehicleIndex = -1
    this.driverIndex = -1

    // Close dropdown when clicking outside
    this._outsideHandler = (e) => {
      if (!this.element.contains(e.target)) {
        this.hideVehicleResults()
        this.hideDriverResults()
      }
    }
    document.addEventListener("pointerdown", this._outsideHandler, { capture: true })

    // Prevent blur-close issues by keeping dropdown open on input blur;
    // outside click handler will close it instead.
    this._stopBlurCloseVehicle = (e) => {
      // no-op; we just don't close on blur anymore
    }
    this._stopBlurCloseDriver = (e) => {
      // no-op
    }

    if (this.hasVehicleInputTarget) {
      this.vehicleInputTarget.addEventListener("blur", this._stopBlurCloseVehicle)
      this.vehicleInputTarget.addEventListener("keydown", (e) => this.onVehicleKeydown(e))
    }

    if (this.hasDriverInputTarget) {
      this.driverInputTarget.addEventListener("blur", this._stopBlurCloseDriver)
      this.driverInputTarget.addEventListener("keydown", (e) => this.onDriverKeydown(e))
    }

    // If edit page already has hidden IDs, show chips
    this.restoreExistingSelections()
  }

  disconnect() {
    document.removeEventListener("pointerdown", this._outsideHandler, { capture: true })

    if (this.hasVehicleInputTarget) {
      this.vehicleInputTarget.removeEventListener("blur", this._stopBlurCloseVehicle)
    }
    if (this.hasDriverInputTarget) {
      this.driverInputTarget.removeEventListener("blur", this._stopBlurCloseDriver)
    }

    this.abortVehicle()
    this.abortDriver()
  }

  // =========================================================
  // VEHICLE SEARCH
  // =========================================================
  vehicleInput() {
    const term = (this.vehicleInputTarget.value || "").trim()

    if (term.length < 2) {
      this.vehicleIndex = -1
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
    this.vehicleIndex = -1

    if (!items.length) {
      this.hideVehicleResults()
      return
    }

    items.forEach((item, idx) => {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className = "list-group-item list-group-item-action search-result-item"
      btn.textContent = item.label || `Vehicle #${item.id}`
      btn.dataset.index = String(idx)
      btn.dataset.itemId = String(item.id)
      btn.dataset.itemLabel = item.label || ""

      // ✅ Critical: pointerdown/mousedown fires BEFORE blur/click
      const handler = (ev) => {
        ev.preventDefault()
        ev.stopPropagation()
        this.selectVehicle(item)
      }
      btn.addEventListener("pointerdown", handler)
      btn.addEventListener("mousedown", handler)

      this.vehicleListTarget.appendChild(btn)
    })

    this.showVehicleResults()
  }

  selectVehicle(item) {
    if (this.hasVehicleHiddenTarget) {
      this.vehicleHiddenTarget.value = item.id
      this.vehicleHiddenTarget.dispatchEvent(new Event("change", { bubbles: true }))
      // helpful if you inspect the form submission
      this.vehicleHiddenTarget.dispatchEvent(new Event("input", { bubbles: true }))
    }

    if (this.hasVehicleSelectedTextTarget) {
      this.vehicleSelectedTextTarget.textContent = item.label || `Vehicle #${item.id}`
    }

    if (this.hasVehicleSelectedTarget) this.vehicleSelectedTarget.style.display = "block"
    this.hideVehicleResults()

    // Clear input but DO NOT blur (blurring can steal focus / cause odd behavior in modals)
    if (this.hasVehicleInputTarget) this.vehicleInputTarget.value = ""
  }

  clearVehicle(ev) {
    ev?.preventDefault()
    if (this.hasVehicleHiddenTarget) {
      this.vehicleHiddenTarget.value = ""
      this.vehicleHiddenTarget.dispatchEvent(new Event("change", { bubbles: true }))
      this.vehicleHiddenTarget.dispatchEvent(new Event("input", { bubbles: true }))
    }
    if (this.hasVehicleSelectedTarget) this.vehicleSelectedTarget.style.display = "none"
    this.vehicleIndex = -1
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

  onVehicleKeydown(e) {
    if (!this.hasVehicleResultsTarget || this.vehicleResultsTarget.style.display !== "block") return
    if (!this.hasVehicleListTarget) return

    const items = Array.from(this.vehicleListTarget.querySelectorAll("button.search-result-item"))
    if (!items.length) return

    if (e.key === "ArrowDown") {
      e.preventDefault()
      this.vehicleIndex = Math.min(this.vehicleIndex + 1, items.length - 1)
      this.highlight(items, this.vehicleIndex)
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      this.vehicleIndex = Math.max(this.vehicleIndex - 1, 0)
      this.highlight(items, this.vehicleIndex)
    } else if (e.key === "Enter") {
      if (this.vehicleIndex >= 0 && items[this.vehicleIndex]) {
        e.preventDefault()
        // simulate selecting the highlighted item
        items[this.vehicleIndex].dispatchEvent(new Event("pointerdown", { bubbles: true }))
      }
    } else if (e.key === "Escape") {
      e.preventDefault()
      this.hideVehicleResults()
    }
  }

  // =========================================================
  // DRIVER SEARCH
  // =========================================================
  driverInput() {
    const term = (this.driverInputTarget.value || "").trim()

    if (term.length < 2) {
      this.driverIndex = -1
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
    this.driverIndex = -1

    if (!items.length) {
      this.hideDriverResults()
      return
    }

    items.forEach((item, idx) => {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className = "list-group-item list-group-item-action search-result-item"
      btn.textContent = item.label || `Driver #${item.id}`
      btn.dataset.index = String(idx)
      btn.dataset.itemId = String(item.id)
      btn.dataset.itemLabel = item.label || ""

      const handler = (ev) => {
        ev.preventDefault()
        ev.stopPropagation()
        this.selectDriver(item)
      }
      btn.addEventListener("pointerdown", handler)
      btn.addEventListener("mousedown", handler)

      this.driverListTarget.appendChild(btn)
    })

    this.showDriverResults()
  }

  selectDriver(item) {
    if (this.hasDriverHiddenTarget) {
      this.driverHiddenTarget.value = item.id
      this.driverHiddenTarget.dispatchEvent(new Event("change", { bubbles: true }))
      this.driverHiddenTarget.dispatchEvent(new Event("input", { bubbles: true }))
    }

    if (this.hasDriverSelectedTextTarget) {
      this.driverSelectedTextTarget.textContent = item.label || `Driver #${item.id}`
    }

    if (this.hasDriverSelectedTarget) this.driverSelectedTarget.style.display = "block"
    this.hideDriverResults()

    if (this.hasDriverInputTarget) this.driverInputTarget.value = ""
  }

  clearDriver(ev) {
    ev?.preventDefault()
    if (this.hasDriverHiddenTarget) {
      this.driverHiddenTarget.value = ""
      this.driverHiddenTarget.dispatchEvent(new Event("change", { bubbles: true }))
      this.driverHiddenTarget.dispatchEvent(new Event("input", { bubbles: true }))
    }
    if (this.hasDriverSelectedTarget) this.driverSelectedTarget.style.display = "none"
    this.driverIndex = -1
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

  onDriverKeydown(e) {
    if (!this.hasDriverResultsTarget || this.driverResultsTarget.style.display !== "block") return
    if (!this.hasDriverListTarget) return

    const items = Array.from(this.driverListTarget.querySelectorAll("button.search-result-item"))
    if (!items.length) return

    if (e.key === "ArrowDown") {
      e.preventDefault()
      this.driverIndex = Math.min(this.driverIndex + 1, items.length - 1)
      this.highlight(items, this.driverIndex)
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      this.driverIndex = Math.max(this.driverIndex - 1, 0)
      this.highlight(items, this.driverIndex)
    } else if (e.key === "Enter") {
      if (this.driverIndex >= 0 && items[this.driverIndex]) {
        e.preventDefault()
        items[this.driverIndex].dispatchEvent(new Event("pointerdown", { bubbles: true }))
      }
    } else if (e.key === "Escape") {
      e.preventDefault()
      this.hideDriverResults()
    }
  }

  // =========================================================
  // Shared helpers
  // =========================================================
  highlight(items, index) {
    items.forEach((el, i) => {
      if (i === index) el.classList.add("active")
      else el.classList.remove("active")
    })
    // keep highlighted item visible
    try { items[index]?.scrollIntoView({ block: "nearest" }) } catch (_) {}
  }

  // =========================================================
  // Restore existing values (edit page)
  // =========================================================
  restoreExistingSelections() {
    // Vehicle
    if (this.hasVehicleHiddenTarget && this.vehicleHiddenTarget.value) {
      if (this.hasVehicleSelectedTarget) this.vehicleSelectedTarget.style.display = "block"
      if (this.hasVehicleSelectedTextTarget) {
        // If your form also renders the current selected vehicle label, replace this text there.
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
