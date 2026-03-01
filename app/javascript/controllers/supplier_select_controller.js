// File: app/javascript/controllers/supplier_select_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "container", "list", "noSuppliers", "clearButton"]
  static values = { suppliers: Array }

  connect() {
    console.log("✅ SupplierSelect controller connected");
    console.log("Suppliers value:", this.suppliersValue);
    
    // Initialize with current selections
    this.updateSelectedSuppliers()
    
    // Override the default mousedown behavior to make selection additive
    this.selectTarget.addEventListener('mousedown', (event) => {
      const option = event.target.closest('option')
      if (!option) return
      
      event.preventDefault() // Prevent default selection behavior
      
      // Toggle the clicked option
      if (option.selected) {
        option.selected = false
      } else {
        option.selected = true
      }
      
      // Trigger our custom update
      this.updateSelectedSuppliers()
    })
    
    // Also handle keyboard navigation
    this.selectTarget.addEventListener('keydown', (event) => {
      if (event.key === ' ' || event.key === 'Space') {
        event.preventDefault()
        const option = event.target.closest('option')
        if (option) {
          // Toggle the focused option
          if (option.selected) {
            option.selected = false
          } else {
            option.selected = true
          }
          this.updateSelectedSuppliers()
        }
      }
    })
    
    // Disable the default change event since we're handling it manually
    this.selectTarget.addEventListener('change', (event) => {
      event.preventDefault()
    })
  }

  updateSelectedSuppliers() {
    console.log("Updating selected suppliers");
    
    // Get all selected options
    const selectedOptions = Array.from(this.selectTarget.selectedOptions)
    const selectedIds = selectedOptions.map(opt => opt.value)
    const selectedTexts = selectedOptions.map(opt => opt.text)
    
    console.log("Selected IDs:", selectedIds);
    console.log("Selected texts:", selectedTexts);
    
    // Clear the list
    this.listTarget.innerHTML = ''
    
    if (selectedIds.length > 0) {
      // Show container and hide no suppliers message
      this.containerTarget.style.display = 'block'
      this.clearButtonTarget.style.display = 'inline-block'
      this.noSuppliersTarget.style.display = 'none'
      
      // Create a badge for each selected supplier
      selectedIds.forEach(id => {
        // Try to find supplier in the value array
        let supplier = this.suppliersValue.find(s => s.id == id)
        
        // If not found, create from selected option text
        if (!supplier) {
          const option = selectedOptions.find(opt => opt.value === id)
          supplier = { 
            id: id, 
            name: option ? option.text : `Supplier ${id}`
          }
        }
        
        console.log("Creating badge for:", supplier);
        const badge = this.createBadge(supplier)
        this.listTarget.appendChild(badge)
      })
    } else {
      // Show container with no suppliers message
      this.containerTarget.style.display = 'block'
      this.clearButtonTarget.style.display = 'none'
      this.noSuppliersTarget.style.display = 'block'
    }
  }

  createBadge(supplier) {
    const badge = document.createElement('span')
    badge.className = 'badge bg-primary p-2 d-inline-flex align-items-center'
    badge.style.fontSize = '0.9rem'
    badge.style.margin = '0.25rem'
    badge.style.transition = 'all 0.2s ease'
    badge.setAttribute('data-supplier-id', supplier.id)
    badge.innerHTML = `
      <i class="bi bi-building me-1"></i>
      <span class="supplier-name">${this.escapeHtml(supplier.name)}</span>
      <button type="button" class="btn-close btn-close-white ms-2" 
              style="font-size: 0.6rem;" 
              data-action="click->supplier-select#removeSupplier"
              data-supplier-id="${supplier.id}">
      </button>
    `
    return badge
  }

  removeSupplier(event) {
    event.preventDefault()
    event.stopPropagation()
    
    const button = event.currentTarget
    const supplierId = button.dataset.supplierId
    
    console.log("Removing supplier:", supplierId);
    
    // Find and deselect the option
    const options = Array.from(this.selectTarget.options)
    const optionToRemove = options.find(opt => opt.value === supplierId)
    
    if (optionToRemove) {
      optionToRemove.selected = false
      this.updateSelectedSuppliers()
    }
  }

  clearAll() {
    console.log("Clearing all suppliers");
    
    // Deselect all options
    Array.from(this.selectTarget.options).forEach(opt => opt.selected = false)
    
    // Update display
    this.updateSelectedSuppliers()
  }
  
  // Helper to escape HTML in supplier names
  escapeHtml(text) {
    if (!text) return ''
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}