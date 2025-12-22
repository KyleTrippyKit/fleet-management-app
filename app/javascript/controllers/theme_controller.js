// app/javascript/controllers/theme_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { theme: String }
  
  connect() {
    // Check if a theme is stored in localStorage
    const storedTheme = localStorage.getItem('selectedTheme')
    if (storedTheme) {
      this.applyTheme(storedTheme)
    }
  }
  
  applyTheme(themeNumber) {
    // Remove any existing theme classes
    document.body.classList.remove('theme-1', 'theme-2', 'theme-3', 'theme-4', 'theme-5')
    
    // Add the selected theme class
    document.body.classList.add(`theme-${themeNumber}`)
    
    // Apply theme-specific styles
    this.applyThemeStyles(themeNumber)
  }
  
  applyThemeStyles(themeNumber) {
    const themes = {
      1: {
        '--bg-primary': '#FFFFFF',
        '--bg-secondary': '#F8F9FA',
        '--bg-card': '#FFFFFF',
        '--border-color': '#E9ECEF',
        '--text-primary': '#212529',
        '--primary-color': '#0055A4',
        '--police-color': '#BF0A30',
        '--ptsc-color': '#F1BE48'
      },
      2: {
        '--bg-primary': '#121826',
        '--bg-secondary': '#1A1F2E',
        '--bg-card': '#1E2435',
        '--border-color': '#2D3748',
        '--text-primary': '#E2E8F0',
        '--primary-color': '#3B82F6',
        '--police-color': '#BF0A30',
        '--ptsc-color': '#F1BE48'
      },
      3: {
        '--bg-primary': 'linear-gradient(135deg, #FFFFFF 0%, #E8F4FD 100%)',
        '--bg-secondary': '#FFFFFF',
        '--bg-card': 'rgba(255, 255, 255, 0.95)',
        '--border-color': 'rgba(191, 10, 48, 0.1)',
        '--text-primary': '#212529',
        '--primary-color': '#0055A4',
        '--police-color': '#BF0A30',
        '--ptsc-color': '#F1BE48'
      },
      4: {
        '--bg-primary': '#F5F7FA',
        '--bg-secondary': '#FFFFFF',
        '--bg-card': '#FFFFFF',
        '--border-color': '#E1E8ED',
        '--text-primary': '#2C3E50',
        '--primary-color': '#0055A4',
        '--police-color': '#BF0A30',
        '--ptsc-color': '#F1BE48'
      },
      5: {
        '--bg-primary': '#F0F2F5',
        '--bg-secondary': '#FFFFFF',
        '--bg-card': 'rgba(255, 255, 255, 0.95)',
        '--border-color': 'rgba(0, 85, 164, 0.1)',
        '--text-primary': '#1A202C',
        '--primary-color': '#0055A4',
        '--police-color': '#BF0A30',
        '--ptsc-color': '#F1BE48'
      }
    }
    
    const theme = themes[themeNumber] || themes[1]
    
    // Apply CSS variables
    Object.entries(theme).forEach(([key, value]) => {
      document.documentElement.style.setProperty(key, value)
    })
  }
  
  // Optional: Method to clear theme
  clearTheme() {
    localStorage.removeItem('selectedTheme')
    document.body.classList.remove('theme-1', 'theme-2', 'theme-3', 'theme-4', 'theme-5')
    // Reset to default theme
    this.applyTheme(1)
  }
}