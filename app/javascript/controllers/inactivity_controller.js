// app/javascript/controllers/inactivity_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { timeout: { type: Number, default: 300000 } } // 5 minutes default
  
  connect() {
    this.timeout = setTimeout(() => {
      window.location.href = '/screensaver'
    }, this.timeoutValue)
    
    this.resetTimeout = this.resetTimeout.bind(this)
    document.addEventListener('mousemove', this.resetTimeout)
    document.addEventListener('keypress', this.resetTimeout)
    document.addEventListener('click', this.resetTimeout)
    document.addEventListener('scroll', this.resetTimeout)
    document.addEventListener('touchstart', this.resetTimeout) // For mobile
  }
  
  resetTimeout() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => {
      window.location.href = '/screensaver'
    }, this.timeoutValue)
  }
  
  disconnect() {
    clearTimeout(this.timeout)
    document.removeEventListener('mousemove', this.resetTimeout)
    document.removeEventListener('keypress', this.resetTimeout)
    document.removeEventListener('click', this.resetTimeout)
    document.removeEventListener('scroll', this.resetTimeout)
    document.removeEventListener('touchstart', this.resetTimeout)
  }
}