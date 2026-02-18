// app/javascript/controllers/quotation_vehicle_search_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "vehicleInput",
    "vehicleHidden",
    "vehicleResults",
    "vehicleList",
    "vehicleSelected",
    "vehicleSelectedText"
  ]

  connect() {
    console.log("✅ Quotation vehicle search controller connected")
    console.log("Targets found:", {
      input: this.hasVehicleInputTarget,
      hidden: this.hasVehicleHiddenTarget,
      results: this.hasVehicleResultsTarget,
      list: this.hasVehicleListTarget,
      selected: this.hasVehicleSelectedTarget,
      selectedText: this.hasVehicleSelectedTextTarget
    })
    
    this.vehicleAbort = null
    this.vehicleDebounce = null
    this.vehicleIndex = -1

    this._outsideHandler = (e) => {
      if (!this.element.contains(e.target)) {
        this.hideVehicleResults()
      }
    }
    document.addEventListener("pointerdown", this._outsideHandler, { capture: true })

    if (this.hasVehicleInputTarget) {
      console.log("✅ Vehicle input target found, adding event listeners")
      this.vehicleInputTarget.addEventListener("keydown", (e) => this.onVehicleKeydown(e))
    }

    this.restoreExistingSelections()
  }

  disconnect() {
    document.removeEventListener("pointerdown", this._outsideHandler, { capture: true })
    this.abortVehicle()
  }

  vehicleInput() {
    const term = (this.vehicleInputTarget.value || "").trim()
    console.log("🔍 Search input:", term)

    if (term.length < 2) {
      console.log("Term too short, hiding results")
      this.vehicleIndex = -1
      this.hideVehicleResults()
      return
    }

    clearTimeout(this.vehicleDebounce)
    this.vehicleDebounce = setTimeout(() => this.fetchVehicles(term), 300)
  }

  async fetchVehicles(term) {
    const url = this.vehicleInputTarget.dataset.searchUrl
    console.log("📡 Fetching from URL:", url)
    
    if (!url) {
      console.error("❌ No search URL found")
      return
    }

    this.abortVehicle()
    this.vehicleAbort = new AbortController()

    const qs = new URLSearchParams({ q: term }).toString()
    const fullUrl = `${url}${url.includes("?") ? "&" : "?"}${qs}`
    console.log("Full URL:", fullUrl)

    try {
      const res = await fetch(fullUrl, {
        headers: { Accept: "application/json" },
        signal: this.vehicleAbort.signal
      })
      console.log("Response status:", res.status)
      
      if (!res.ok) throw new Error(`Vehicle search failed (${res.status})`)
      const data = await res.json()
      console.log("Received data:", data)
      this.renderVehicleResults(Array.isArray(data) ? data : [])
    } catch (e) {
      if (e.name === "AbortError") {
        console.log("Request aborted")
        return
      }
      console.warn("Vehicle search error:", e)
      this.renderVehicleResults([])
    }
  }

  renderVehicleResults(items) {
    console.log("Rendering items:", items.length)
    
    if (!this.hasVehicleListTarget) {
      console.error("❌ Vehicle list target not found")
      return
    }

    this.vehicleListTarget.innerHTML = ""
    this.vehicleIndex = -1

    if (!items.length) {
      console.log("No items to render")
      this.hideVehicleResults()
      return
    }

    items.forEach((item, idx) => {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className = "list-group-item list-group-item-action search-result-item"
      
      const displayText = item.license_plate 
        ? `${item.license_plate} • ${item.make || ''} ${item.model || ''} • ${item.agency_code || 'No Agency'}`
        : `${item.make || ''} ${item.model || ''} • ${item.agency_code || 'No Agency'}`
      
      btn.textContent = displayText
      btn.dataset.index = String(idx)
      btn.dataset.itemId = String(item.id)
      btn.dataset.itemLabel = displayText
      btn.dataset.itemAgency = item.agency_code || ''

      const handler = (ev) => {
        ev.preventDefault()
        ev.stopPropagation()
        console.log("Selected item:", item)
        this.selectVehicle(item, displayText)
      }
      btn.addEventListener("pointerdown", handler)
      btn.addEventListener("mousedown", handler)

      this.vehicleListTarget.appendChild(btn)
    })

    console.log("Items added to list, showing results")
    this.showVehicleResults()
  }

  selectVehicle(item, displayText) {
    console.log("Selecting vehicle:", item.id, displayText)
    
    if (this.hasVehicleHiddenTarget) {
      this.vehicleHiddenTarget.value = item.id
      this.vehicleHiddenTarget.dispatchEvent(new Event("change", { bubbles: true }))
      this.vehicleHiddenTarget.dispatchEvent(new Event("input", { bubbles: true }))
      console.log("Hidden field set to:", item.id)
    }

    if (this.hasVehicleSelectedTextTarget) {
      this.vehicleSelectedTextTarget.textContent = displayText
      console.log("Selected text set")
    }

    if (this.hasVehicleSelectedTarget) {
      this.vehicleSelectedTarget.style.display = "block"
      console.log("Selected chip shown")
    }
    
    this.hideVehicleResults()

    if (this.hasVehicleInputTarget) {
      this.vehicleInputTarget.value = ""
      console.log("Input cleared")
    }
  }

  clearVehicle(ev) {
    console.log("Clearing vehicle selection")
    ev?.preventDefault()
    if (this.hasVehicleHiddenTarget) {
      this.vehicleHiddenTarget.value = ""
      this.vehicleHiddenTarget.dispatchEvent(new Event("change", { bubbles: true }))
      this.vehicleHiddenTarget.dispatchEvent(new Event("input", { bubbles: true }))
    }
    if (this.hasVehicleSelectedTarget) this.vehicleSelectedTarget.style.display = "none"
    this.vehicleIndex = -1
    this.hideVehicleResults()
    
    if (this.hasVehicleInputTarget) {
      this.vehicleInputTarget.value = ""
      this.vehicleInputTarget.focus()
    }
  }

  showVehicleResults() {
    if (this.hasVehicleResultsTarget) {
      this.vehicleResultsTarget.style.display = "block"
      console.log("Results container display set to block")
    }
  }

  hideVehicleResults() {
    if (this.hasVehicleResultsTarget) {
      this.vehicleResultsTarget.style.display = "none"
      console.log("Results container hidden")
    }
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
        const selectedItem = {
          id: items[this.vehicleIndex].dataset.itemId,
          license_plate: items[this.vehicleIndex].textContent.split(' • ')[0],
          make: '',
          model: '',
          agency_code: items[this.vehicleIndex].dataset.itemAgency
        }
        this.selectVehicle(selectedItem, items[this.vehicleIndex].textContent)
      }
    } else if (e.key === "Escape") {
      e.preventDefault()
      this.hideVehicleResults()
    }
  }

  highlight(items, index) {
    items.forEach((el, i) => {
      if (i === index) el.classList.add("active")
      else el.classList.remove("active")
    })
    try { items[index]?.scrollIntoView({ block: "nearest" }) } catch (_) {}
  }

  restoreExistingSelections() {
    if (this.hasVehicleHiddenTarget && this.vehicleHiddenTarget.value) {
      console.log("Existing vehicle selected:", this.vehicleHiddenTarget.value)
      if (this.hasVehicleSelectedTarget) this.vehicleSelectedTarget.style.display = "block"
    } else {
      if (this.hasVehicleSelectedTarget) this.vehicleSelectedTarget.style.display = "none"
    }
  }
}