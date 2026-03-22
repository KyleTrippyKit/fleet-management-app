import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { timeout: { type: Number, default: 30000 } }
  
  connect() {
    // Skip inactivity timer on dashboard pages
    const currentPath = window.location.pathname;
    if (currentPath.includes('/inventory_dashboard') || 
        currentPath.includes('/dashboard')) {
      console.log("⏰ Inactivity controller disabled for dashboard page");
      return;
    }
    
    // Skip on screensaver page
    if (currentPath.includes('/screensaver')) {
      console.log("⏰ On screensaver page, not starting inactivity timer");
      return;
    }
    
    console.log("⏰ Inactivity controller connected with timeout:", this.timeoutValue);
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
    const currentPath = window.location.pathname;
    if (!currentPath.includes('/screensaver') && 
        currentPath !== '/' &&
        !currentPath.includes('/inventory_dashboard')) {
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
