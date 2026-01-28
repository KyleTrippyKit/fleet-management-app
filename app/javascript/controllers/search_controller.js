// app/javascript/controllers/search_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item", "input"]
  
  connect() {
    // Initialize if needed
  }
  
  perform(event) {
    const searchTerm = this.inputTarget.value.toLowerCase().trim()
    
    this.itemTargets.forEach((element) => {
      const text = element.textContent.toLowerCase()
      
      if (searchTerm === '') {
        element.style.display = "block"
      } else {
        element.style.display = text.includes(searchTerm) ? "block" : "none"
      }
    })
  }
}

// app/javascript/controllers/invoice_search_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]
  static values = { url: String }
  
  search() {
    const query = this.inputTarget.value.trim()
    
    if (query.length > 2) {
      clearTimeout(this.timeout)
      
      this.timeout = setTimeout(() => {
        fetch(`${this.urlValue}?q=${encodeURIComponent(query)}`)
          .then(response => response.json())
          .then(data => this.handleResults(data))
          .catch(error => console.error('Search error:', error))
      }, 300)
    }
  }
  
  handleResults(data) {
    // Custom implementation based on where this is used
    console.log('Search results:', data)
    // You can dispatch a custom event or update the DOM
    const event = new CustomEvent('invoice-search:results', { detail: data })
    document.dispatchEvent(event)
  }
}