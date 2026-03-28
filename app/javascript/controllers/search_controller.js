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