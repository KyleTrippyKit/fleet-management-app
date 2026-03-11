// app/javascript/controllers/inactivity_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { timeout: { type: Number, default: 30000 } } // 30 seconds default
  
  connect() {
    console.log("⏰ Inactivity controller connected with timeout:", this.timeoutValue);
    
    // Don't set up timer if we're on the screensaver page
    if (window.location.pathname.includes('/screensaver')) {
      console.log("⏰ On screensaver page, not starting inactivity timer");
      return;
    }
    
    this.setupTimer();
    this.setupListeners();
  }
  
  setupTimer() {
    this.timeout = setTimeout(() => {
      this.redirectToScreensaver();
    }, this.timeoutValue);
  }
  
  setupListeners() {
    this.resetTimeout = this.resetTimeout.bind(this);
    this.activityEvents = ['mousemove', 'keypress', 'click', 'scroll', 'touchstart'];
    this.activityEvents.forEach(event => {
      document.addEventListener(event, this.resetTimeout);
    });
  }
  
  resetTimeout() {
    clearTimeout(this.timeout);
    this.setupTimer();
  }
  
  redirectToScreensaver() {
    // Don't redirect if already on screensaver or home page
    const currentPath = window.location.pathname;
    if (!currentPath.includes('/screensaver') && currentPath !== '/') {
      console.log("⏰ Inactivity timeout reached, redirecting to screensaver");
      window.location.href = '/screensaver';
    }
  }
  
  disconnect() {
    console.log("⏰ Inactivity controller disconnecting");
    clearTimeout(this.timeout);
    if (this.activityEvents) {
      this.activityEvents.forEach(event => {
        document.removeEventListener(event, this.resetTimeout);
      });
    }
  }
}