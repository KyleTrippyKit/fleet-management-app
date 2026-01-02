// app/javascript/controllers/theme_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { 
    theme: String,
    themeTestMode: Boolean 
  }

  connect() {
    console.log("🎨 Theme Controller connected");
    
    // Skip theme on Gantt pages
    if (this.isGanttPage()) {
      console.log("🎨 On Gantt page - skipping theme initialization");
      this.disableThemeOnGanttPage();
      return;
    }
    
    // Check URL for theme parameter first
    const urlParams = new URLSearchParams(window.location.search);
    const themeFromURL = urlParams.get('theme');
    
    if (themeFromURL && this.isValidTheme(themeFromURL)) {
      console.log("🎨 Theme from URL:", themeFromURL);
      this.themeValue = themeFromURL;
      localStorage.setItem('selectedTheme', themeFromURL);
      localStorage.setItem('themeTestMode', 'true');
      this.applyTheme(themeFromURL);
      return;
    }
    
    // Then check localStorage
    const savedTheme = localStorage.getItem('selectedTheme');
    const themeTestMode = localStorage.getItem('themeTestMode') === 'true';
    
    if (savedTheme && this.isValidTheme(savedTheme) && themeTestMode) {
      console.log("🎨 Theme from localStorage:", savedTheme);
      this.themeValue = savedTheme;
      this.applyTheme(savedTheme);
      this.showThemePreviewAlert(savedTheme);
    }
  }

  // Check if current page is a Gantt page
  isGanttPage() {
    // Check if :gantt_page content is set
    const ganttPageMeta = document.querySelector('meta[name="gantt-page"]');
    if (ganttPageMeta) return true;
    
    // Check for gantt container elements
    const hasGanttElements = document.getElementById('ganttContainer') !== null ||
                            document.querySelector('[data-gantt-tasks]') !== null ||
                            document.getElementById('ganttData') !== null;
    
    // Check URL path
    const isGanttPath = window.location.pathname.includes('/gantt');
    
    // Check Rails content_for marker (you might need to add this to your layout)
    const hasGanttContent = document.body.dataset.page === 'gantt' || 
                           document.body.classList.contains('gantt-page');
    
    return hasGanttElements || isGanttPath || hasGanttContent;
  }

  // Disable theme functionality on Gantt pages
  disableThemeOnGanttPage() {
    console.log("🎨 Disabling theme on Gantt page");
    
    // Add gantt-page class for CSS targeting
    document.body.classList.add('gantt-page', 'gantt-neutral');
    
    // Remove any existing theme classes
    document.body.classList.remove('theme-1', 'theme-2', 'theme-3', 'theme-4', 'theme-5', 
      'theme-6', 'theme-7', 'theme-8', 'theme-9', 'theme-10', 'theme-11');
    
    // Hide any theme alert if it exists
    const themeAlert = document.getElementById('themePreviewAlert');
    if (themeAlert) {
      themeAlert.style.display = 'none';
    }
    
    // Add a meta tag to mark this as a Gantt page
    const meta = document.createElement('meta');
    meta.name = 'page-type';
    meta.content = 'gantt';
    document.head.appendChild(meta);
    
    // Dispatch event that theme is disabled
    document.dispatchEvent(new CustomEvent('theme:disabled'));
  }

  themeValueChanged() {
    if (this.themeValue) {
      this.applyTheme(this.themeValue);
    }
  }

  // All available themes with their details
  themes = {
    1: { 
      name: "Modern Light", 
      icon: "☀️", 
      description: "Professional dashboard suitable for daily operations and reporting." 
    },
    2: { 
      name: "Dark Professional", 
      icon: "🌙", 
      description: "Eye-friendly interface that makes vehicle status colors stand out." 
    },
    3: { 
      name: "Trinidad Gradient", 
      icon: "🇹🇹", 
      description: "Patriotic theme using Trinidad & Tobago national colors." 
    },
    4: { 
      name: "Clean Admin", 
      icon: "⚙️", 
      description: "Traditional admin panel with sidebar navigation." 
    },
    5: { 
      name: "Map-Centric", 
      icon: "🗺️", 
      description: "Optimized for real-time tracking with map visualization." 
    },
    6: { 
      name: "Emergency Response", 
      icon: "🚨", 
      description: "High-visibility emergency vehicle theme with alert colors." 
    },
    7: { 
      name: "Coastal/Tropical", 
      icon: "🏖️", 
      description: "Beach-inspired theme with ocean blues, sand beige, and palm greens." 
    },
    8: { 
      name: "Modern Tech", 
      icon: "💻", 
      description: "Futuristic tech interface with dark mode, neon accents, and grid backgrounds." 
    },
    9: { 
      name: "Classic/Vintage", 
      icon: "📜", 
      description: "Retro theme with aged paper effects and classic colors." 
    },
    10: { 
      name: "Luxury/Executive", 
      icon: "💎", 
      description: "Premium dark theme with gold accents and elegant styling." 
    },
    11: { 
      name: "Corporate/Professional", 
      icon: "🏢", 
      description: "Clean corporate design with blue and gray tones." 
    }
  }

  isValidTheme(themeNumber) {
    return this.themes[themeNumber] !== undefined;
  }

  // Apply theme to the page
  applyTheme(themeNumber) {
    // Don't apply theme on Gantt pages
    if (this.isGanttPage()) {
      console.log("🎨 Skipping theme application on Gantt page");
      return;
    }
    
    console.log("🎨 Applying theme:", themeNumber);
    
    // Remove all theme classes
    document.body.classList.remove('theme-1', 'theme-2', 'theme-3', 'theme-4', 'theme-5', 
      'theme-6', 'theme-7', 'theme-8', 'theme-9', 'theme-10', 'theme-11', 'gantt-page', 'gantt-neutral');
    
    // Apply the selected theme class
    document.body.classList.add(`theme-${themeNumber}`);
    
    // Update data attribute
    this.element.dataset.themeValue = themeNumber;
    
    // Save to localStorage
    localStorage.setItem('selectedTheme', themeNumber);
    localStorage.setItem('themeTestMode', 'true');
    
    // Show theme preview alert
    this.showThemePreviewAlert(themeNumber);
    
    // Dispatch custom event for other controllers
    document.dispatchEvent(new CustomEvent('theme:changed', {
      detail: { theme: themeNumber }
    }));
  }

  // Show theme preview alert
  showThemePreviewAlert(themeNumber) {
    // Don't show alert on Gantt pages
    if (this.isGanttPage()) {
      return;
    }
    
    const themeInfo = this.themes[themeNumber];
    if (!themeInfo) return;
    
    // Check if alert already exists
    let alertDiv = document.getElementById('themePreviewAlert');
    
    if (!alertDiv) {
      alertDiv = document.createElement('div');
      alertDiv.id = 'themePreviewAlert';
      alertDiv.className = 'theme-preview-alert';
      // Insert at the top of the body
      document.body.insertBefore(alertDiv, document.body.firstChild);
    }
    
    alertDiv.innerHTML = `
      <div class="alert alert-warning alert-dismissible fade show mb-0 rounded-0" role="alert">
        <div class="container-fluid">
          <div class="d-flex justify-content-between align-items-center">
            <div>
              <i class="fas fa-palette me-2"></i>
              <strong>Theme Preview Active:</strong> ${themeInfo.name}
              <span class="ms-2 small">Changes are temporary</span>
            </div>
            <div>
              <button data-action="click->theme#clearTheme" class="btn btn-sm btn-outline-danger">
                <i class="fas fa-times me-1"></i> Clear Theme
              </button>
            </div>
          </div>
        </div>
      </div>
    `;
    
    alertDiv.style.display = 'block';
  }

  // Clear theme preview
  clearTheme() {
    console.log("🎨 Clearing theme preview");
    
    // Remove theme class
    document.body.classList.remove('theme-1', 'theme-2', 'theme-3', 'theme-4', 'theme-5', 
      'theme-6', 'theme-7', 'theme-8', 'theme-9', 'theme-10', 'theme-11', 'gantt-page', 'gantt-neutral');
    
    // Clear localStorage
    localStorage.removeItem('selectedTheme');
    localStorage.removeItem('themeTestMode');
    
    // Hide alert
    const alertDiv = document.getElementById('themePreviewAlert');
    if (alertDiv) {
      alertDiv.style.display = 'none';
    }
    
    // Clear data attribute
    this.element.dataset.themeValue = '';
    
    // Dispatch theme cleared event
    document.dispatchEvent(new CustomEvent('theme:cleared'));
  }

  // Select theme from button/link
  selectTheme(event) {
    event.preventDefault();
    const themeNumber = event.currentTarget.dataset.theme;
    if (this.isValidTheme(themeNumber)) {
      this.applyTheme(themeNumber);
    }
  }
}