// app/javascript/controllers/theme_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["themeButton"]
  
  connect() {
    console.log("🎨 Theme controller connected");
    
    // Check for Gantt pages first
    if (this.isGanttPage()) {
      console.log("🎨 Gantt page detected - skipping theme initialization");
      this.disableThemeOnGanttPage();
      return;
    }
    
    // Check URL for theme parameter first (for testing)
    const urlParams = new URLSearchParams(window.location.search);
    const themeFromURL = urlParams.get('theme');
    
    if (themeFromURL && this.isValidTheme(themeFromURL)) {
      console.log("🎨 Theme from URL:", themeFromURL);
      localStorage.setItem('selectedTheme', themeFromURL);
      localStorage.setItem('themeTestMode', 'true');
      this.apply(themeFromURL);
      this.showThemePreviewAlert(themeFromURL);
      return;
    }
    
    // Check if we're on a VMCOTT page
    const isVmcottPath = window.location.pathname.startsWith('/vmcott');
    
    // Get saved theme
    const saved = localStorage.getItem("selectedTheme");
    const themeTestMode = localStorage.getItem('themeTestMode') === 'true';
    
    // Determine which theme to apply
    let themeToApply = "9"; // Default to theme 9
    
    if (saved && themeTestMode) {
      // Use saved theme if in test mode
      themeToApply = saved;
    } else if (saved && !isVmcottPath) {
      // Use saved theme for non-VMCOTT pages
      themeToApply = saved;
    } else if (isVmcottPath) {
      // VMCOTT pages get theme 9 by default
      themeToApply = "9";
    } else {
      // Non-VMCOTT pages with no saved theme
      const agencyTheme = this.getAgencyTheme();
      themeToApply = agencyTheme || "1"; // Fallback to theme 1
    }
    
    console.log(`🎨 Applying theme: ${themeToApply} (VMCOTT: ${isVmcottPath}, Saved: ${saved}, TestMode: ${themeTestMode})`);
    this.apply(themeToApply);
  }

  setTheme(event) {
    const theme = event?.params?.theme || event?.target?.dataset?.theme;
    if (!theme || !this.isValidTheme(theme)) {
      console.error("🎨 Invalid theme:", theme);
      return;
    }
    
    console.log("🎨 Setting theme:", theme);
    localStorage.setItem("selectedTheme", theme);
    localStorage.setItem('themeTestMode', 'true');
    this.apply(theme);
    this.showThemePreviewAlert(theme);
    
    // Dispatch custom event for other controllers
    document.dispatchEvent(new CustomEvent('theme:changed', {
      detail: { theme: theme }
    }));
  }

  apply(theme) {
    if (!this.isValidTheme(theme)) {
      console.error("🎨 Cannot apply invalid theme:", theme);
      theme = "1"; // Fallback to theme 1
    }
    
    // Remove all theme classes
    const allThemeClasses = Array.from({length: 11}, (_, i) => `theme-${i + 1}`);
    document.body.classList.remove(...allThemeClasses);
    
    // Apply the selected theme
    document.body.classList.add(`theme-${theme}`);
    
    // Update data attribute
    this.element.dataset.themeValue = theme;
    
    console.log("🎨 Theme applied:", theme);
  }

  clearTheme(event) {
    event?.preventDefault();
    console.log("🎨 Clearing theme settings");
    
    localStorage.removeItem("selectedTheme");
    localStorage.removeItem('themeTestMode');
    
    // Remove theme preview alert if it exists
    const alertDiv = document.getElementById('themePreviewAlert');
    if (alertDiv) {
      alertDiv.style.display = 'none';
    }
    
    // Check if we're on a VMCOTT page
    const isVmcottPath = window.location.pathname.startsWith('/vmcott');
    
    // Apply default theme
    let defaultTheme = isVmcottPath ? "9" : (this.getAgencyTheme() || "1");
    this.apply(defaultTheme);
    
    // Dispatch theme cleared event
    document.dispatchEvent(new CustomEvent('theme:cleared'));
  }

  // Helper methods
  isValidTheme(themeNumber) {
    const themeNum = parseInt(themeNumber, 10);
    return !isNaN(themeNum) && themeNum >= 1 && themeNum <= 11;
  }

  getAgencyTheme() {
    // Try to get agency theme from meta tag or data attribute
    const agencyMeta = document.querySelector('meta[name="agency-theme"]');
    if (agencyMeta) {
      return agencyMeta.getAttribute('content');
    }
    
    // Check body data attribute
    const bodyTheme = document.body.dataset.agencyTheme;
    if (bodyTheme) {
      return bodyTheme;
    }
    
    return null;
  }

  isGanttPage() {
    // Check meta tag
    const ganttMeta = document.querySelector('meta[name="page-type"]');
    if (ganttMeta?.content === 'gantt') return true;
    
    // Check body classes
    if (document.body.classList.contains('gantt-page')) return true;
    
    // Check for gantt-specific elements
    if (document.getElementById('ganttContainer') || 
        document.querySelector('[data-gantt-tasks]') ||
        document.getElementById('ganttData')) {
      return true;
    }
    
    // Check URL
    return window.location.pathname.includes('/gantt');
  }

  disableThemeOnGanttPage() {
    console.log("🎨 Disabling theme on Gantt page");
    
    // Remove all theme classes
    const allThemeClasses = Array.from({length: 11}, (_, i) => `theme-${i + 1}`);
    document.body.classList.remove(...allThemeClasses);
    
    // Add neutral gantt class
    document.body.classList.add('gantt-page', 'gantt-neutral');
  }

  showThemePreviewAlert(themeNumber) {
    // Don't show on Gantt pages
    if (this.isGanttPage()) return;
    
    // Remove existing alert if any
    const existingAlert = document.getElementById('themePreviewAlert');
    if (existingAlert) existingAlert.remove();
    
    const themeNames = {
      1: "Modern Light",
      2: "Dark Professional", 
      3: "Trinidad Gradient",
      4: "Clean Admin",
      5: "Map-Centric",
      6: "Emergency Response",
      7: "Coastal/Tropical",
      8: "Modern Tech",
      9: "Classic/Vintage",
      10: "Luxury/Executive",
      11: "Corporate/Professional"
    };
    
    const themeName = themeNames[themeNumber] || `Theme ${themeNumber}`;
    
    const alertDiv = document.createElement('div');
    alertDiv.id = 'themePreviewAlert';
    alertDiv.innerHTML = `
      <div class="alert alert-warning alert-dismissible fade show mb-0 rounded-0" role="alert">
        <div class="container-fluid">
          <div class="d-flex justify-content-between align-items-center">
            <div>
              <i class="bi bi-palette me-2"></i>
              <strong>Theme Preview Active:</strong> ${themeName}
              <span class="ms-2 small">Changes are temporary</span>
            </div>
            <div>
              <button type="button" class="btn btn-sm btn-outline-danger" data-action="click->theme#clearTheme">
                <i class="bi bi-x-circle me-1"></i> Clear Theme
              </button>
            </div>
          </div>
        </div>
      </div>
    `;
    
    // Insert at the top of the body
    document.body.insertBefore(alertDiv, document.body.firstChild);
  }
}