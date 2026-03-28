// app/javascript/controllers/invoice_search_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]
  static values = { url: String }
  
  connect() {
    console.log("✅ Invoice search controller connected")
  }
  
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
    console.log('Search results:', data)
    const event = new CustomEvent('invoice-search:results', { detail: data })
    document.dispatchEvent(event)
  }
}
