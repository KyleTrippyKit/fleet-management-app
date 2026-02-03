import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    const message = this.element.dataset.message
    if (message && message.trim().length > 0) {
      alert(message)
    }
  }
}
