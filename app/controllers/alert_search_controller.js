// app/javascript/controllers/alert_search_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    // Vehicle
    "vehicleInput", "vehicleResults", "vehicleList",
    "vehicleSelected", "vehicleSelectedText", "vehicleHidden", "vehicleClear",

    // Driver
    "driverInput", "driverResults", "driverList",
    "driverSelected", "driverSelectedText", "driverHidden", "driverClear"
  ]

  connect() {
    // Prevent double-binding issues (Stimulus handles lifecycle)
    this.vehicleTimer = null
    this.driverTimer = null

    // Close dropdowns on outside click (capture phase so it runs before random bubbling logic)
    this.boundOutside = this.onOutsidePointerDown.bind(this)
    document.addEventListener("pointerdown", this.boundOutside, true)

    // Stop clicks inside dropdowns from triggering outside logic elsewhere
    this.vehicleResultsTarget?.addEventListener("pointerdown", (e) => e.stopPropagation(), true)
    this.driverResultsTarget?.addEventListener("pointerdown", (e) => e.stopPropagation(), true)

    // If user hits Enter in the search input, prevent form submit
    this.vehicleInputTarget?.addEventListener("keydown", (e) => {
      if (e.key === "Enter") e.preventDefault()
    })
    this.driverInputTarget?.addEventListener("keydown", (e) => {
      if (e.key === "Enter") e.preventDefault()
    })
  }

  disconnect() {
    document.removeEventListener("pointerdown", this.boundOutside, true)
    clearTimeout(this.vehicleTimer)
    clearTimeout(this.driverTimer)
  }

  // ---------- Vehicle ----------
  vehicleInput() {
    clearTimeout(this.vehicleTimer)
    const q = (this.vehicleInputTarget.value || "").trim()
    if (q.length < 2) return this.hide(this.vehicleResultsTarget)

    this.vehicleTimer = setTimeout(async () => {
      const url = this.vehicleInputTarget.dataset.searchUrl
      if (!url) return

      try {
        const res = await fetch(`${url}?q=${encodeURIComponent(q)}`, {
          headers: { Accept: "application/json" }
        })
        const data = await res.json()
        this.renderVehicles(Array.isArray(data) ? data : [])
      } catch (e) {
        this.vehicleListTarget.innerHTML =
          `<div class="list-group-item text-danger">Error searching vehicles</div>`
        this.show(this.vehicleResultsTarget)
      }
    }, 200)
  }

  renderVehicles(vehicles) {
    this.vehicleListTarget.innerHTML = ""

    if (vehicles.length === 0) {
      this.vehicleListTarget.innerHTML =
        `<div class="list-group-item text-muted">No vehicles found</div>`
      return this.show(this.vehicleResultsTarget)
    }

    vehicles.forEach((v) => {
      const item = document.createElement("button")
      item.type = "button"
      item.className = "list-group-item list-group-item-action search-result-item text-start"
      const badge = v.agency_code || v.service_owner || "N/A"

      item.innerHTML = `
        <div class="d-flex justify-content-between">
          <div>
            <strong>${v.license_plate || ""}</strong>
            <div class="text-muted small">
              ${(v.make || "")} ${(v.model || "")} • ${(v.registration_number || "No reg")}
            </div>
          </div>
          <div><span class="badge bg-secondary">${badge}</span></div>
        </div>
      `

      // ✅ Use pointerdown in CAPTURE to beat any other global handlers
      item.addEventListener("pointerdown", (e) => {
        e.preventDefault()
        e.stopPropagation()
        this.selectVehicle(v)
      }, true)

      this.vehicleListTarget.appendChild(item)
    })

    this.show(this.vehicleResultsTarget)
  }

  selectVehicle(v) {
    this.vehicleHiddenTarget.value = v.id
    this.vehicleSelectedTextTarget.textContent = `${v.license_plate} - ${v.make} ${v.model}`
    this.show(this.vehicleSelectedTarget)
    this.hide(this.vehicleResultsTarget)

    // Leave the search box empty for next search
    this.vehicleInputTarget.value = ""
  }

  clearVehicle() {
    this.vehicleHiddenTarget.value = ""
    this.hide(this.vehicleSelectedTarget)
    this.vehicleInputTarget.value = ""
    this.vehicleInputTarget.focus()
  }

  // ---------- Driver ----------
  driverInput() {
    clearTimeout(this.driverTimer)
    const q = (this.driverInputTarget.value || "").trim()
    if (q.length < 2) return this.hide(this.driverResultsTarget)

    this.driverTimer = setTimeout(async () => {
      const url = this.driverInputTarget.dataset.searchUrl
      if (!url) return

      try {
        const res = await fetch(`${url}?q=${encodeURIComponent(q)}`, {
          headers: { Accept: "application/json" }
        })
        const data = await res.json()
        this.renderDrivers(Array.isArray(data) ? data : [])
      } catch (e) {
        this.driverListTarget.innerHTML =
          `<div class="list-group-item text-danger">Error searching drivers</div>`
        this.show(this.driverResultsTarget)
      }
    }, 200)
  }

  renderDrivers(drivers) {
    this.driverListTarget.innerHTML = ""

    if (drivers.length === 0) {
      this.driverListTarget.innerHTML =
        `<div class="list-group-item text-muted">No drivers found</div>`
      return this.show(this.driverResultsTarget)
    }

    drivers.forEach((d) => {
      const item = document.createElement("button")
      item.type = "button"
      item.className = "list-group-item list-group-item-action search-result-item text-start"
      const phone = d.contact_number || d.phone || "No phone"

      item.innerHTML = `
        <div class="d-flex justify-content-between">
          <div>
            <strong>${d.name || ""}</strong>
            <div class="text-muted small">
              ${(d.license_number || "No license")} • ${phone}
            </div>
          </div>
          <div><span class="badge bg-info">${d.status || "active"}</span></div>
        </div>
      `

      item.addEventListener("pointerdown", (e) => {
        e.preventDefault()
        e.stopPropagation()
        this.selectDriver(d)
      }, true)

      this.driverListTarget.appendChild(item)
    })

    this.show(this.driverResultsTarget)
  }

  selectDriver(d) {
    this.driverHiddenTarget.value = d.id
    this.driverSelectedTextTarget.textContent =
      `${d.name} (${d.license_number || "No license"})`
    this.show(this.driverSelectedTarget)
    this.hide(this.driverResultsTarget)

    this.driverInputTarget.value = ""
  }

  clearDriver() {
    this.driverHiddenTarget.value = ""
    this.hide(this.driverSelectedTarget)
    this.driverInputTarget.value = ""
    this.driverInputTarget.focus()
  }

  // ---------- Outside click ----------
  onOutsidePointerDown(e) {
    // If click is inside the controller element, ignore
    if (this.element.contains(e.target)) return

    // Otherwise close dropdowns only (do not clear selection)
    this.hide(this.vehicleResultsTarget)
    this.hide(this.driverResultsTarget)
  }

  // ---------- utils ----------
  show(el) { if (el) el.style.display = "block" }
  hide(el) { if (el) el.style.display = "none" }
}
