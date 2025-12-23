// app/javascript/controllers/theme_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { theme: String }
  
  connect() {
    console.log("🎨 Theme Stimulus Controller connected with theme:", this.themeValue);
    this.applyTheme();
  }
  
  themeValueChanged() {
    console.log("🎨 Theme changed to:", this.themeValue);
    this.applyTheme();
  }
  
  applyTheme() {
    if (this.themeValue && window.themeController) {
      window.themeController.applyTheme(this.themeValue);
    }
  }
  
  // Method to change theme from other controllers
  changeTheme(event) {
    const themeNumber = event.params.theme || event.detail.theme;
    if (themeNumber) {
      this.themeValue = themeNumber;
      
      // Also update session via AJAX if needed
      fetch('/set_theme', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ theme: themeNumber })
      });
    }
  }
}