// app/javascript/controllers/agency_assign_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    agencies: Array,
    currentUserAgency: String
  }

  connect() {
    // Only run for non-VMCOTT users
    if (this.currentUserAgencyValue !== "VMCOTT") {
      return
    }

    // Map service_owner to agency codes
    this.agencyMap = {
      'PTSC': 'PTSC',
      'Police': 'TTPS', 
      'Fire Service': 'TTDF'
    }
    
    // When service_owner changes, auto-select agency
    this.element.addEventListener('change', this.handleServiceOwnerChange.bind(this))
  }

  handleServiceOwnerChange(event) {
    const serviceOwner = event.target.value
    const agencyCode = this.agencyMap[serviceOwner]
    
    if (agencyCode) {
      // Find the agency select element
      const agencySelect = document.getElementById('vehicle_agency_id')
      if (agencySelect) {
        // Find option with agency code in text
        Array.from(agencySelect.options).forEach(option => {
          if (option.text.includes(agencyCode)) {
            agencySelect.value = option.value
          }
        })
      }
    }
  }
}