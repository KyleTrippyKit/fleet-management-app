import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { theme: String }

  connect() {
    console.log("🎨 Theme Stimulus Controller connected");

    // Apply saved theme on page load
    const savedTheme = localStorage.getItem('selectedTheme');
    if (savedTheme) {
      this.themeValue = savedTheme;
      this.applyTheme();
      this.updateThemeDisplay(savedTheme);
    }
  }

  themeValueChanged() {
    this.applyTheme();
  }

  // --- THEMES OBJECT ---
  themes = {
    1: { name: "Modern Light", icon: "☀️", class: "theme-1", description: "Professional dashboard suitable for daily operations and reporting." },
    2: { name: "Dark Professional", icon: "🌙", class: "theme-2", description: "Eye-friendly interface that makes vehicle status colors stand out." },
    3: { name: "Trinidad Gradient", icon: "🇹🇹", class: "theme-3", description: "Patriotic theme using Trinidad & Tobago national colors." },
    4: { name: "Clean Admin", icon: "⚙️", class: "theme-4", description: "Traditional admin panel with sidebar navigation." },
    5: { name: "Map-Centric", icon: "🗺️", class: "theme-5", description: "Optimized for real-time tracking with map visualization." },
    6: { name: "Emergency Response", icon: "🚨", class: "theme-6", description: "High-visibility emergency vehicle theme with alert colors." },
    7: { name: "Coastal/Tropical", icon: "🏖️", class: "theme-7", description: "Beach-inspired theme with ocean blues, sand beige, and palm greens." },
    8: { name: "Modern Tech", icon: "💻", class: "theme-8", description: "Futuristic tech interface with dark mode, neon accents, and grid backgrounds." },
    9: { name: "Classic/Vintage", icon: "📜", class: "theme-9", description: "Retro theme with aged paper effects and classic colors." },
    10: { name: "Luxury/Executive", icon: "💎", class: "theme-10", description: "Premium dark theme with gold accents and elegant styling." },
    11: { name: "Corporate/Professional", icon: "🏢", class: "theme-11", description: "Clean corporate design with blue and gray tones." }
  }

  // --- APPLY THEME ---
  applyTheme() {
    if (!this.themeValue) return;

    // Remove previous theme-* classes
    document.body.className = document.body.className
      .split(' ')
      .filter(c => !c.startsWith('theme-'))
      .join(' ');

    const themeInfo = this.themes[this.themeValue];
    if (!themeInfo) return;

    // Apply new theme class
    document.body.classList.add(themeInfo.class);

    // Save selection
    localStorage.setItem('selectedTheme', this.themeValue);

    // Update display
    this.updateThemeDisplay(this.themeValue);
  }

  // --- SELECT THEME ---
  selectTheme(event) {
    const themeNumber = event.currentTarget.dataset.theme;
    if (!themeNumber) return;

    this.themeValue = themeNumber;
    this.applyTheme();
  }

  // --- UPDATE THEME DISPLAY PANEL ---
  updateThemeDisplay(themeNumber) {
    const themeInfo = this.themes[themeNumber];
    if (!themeInfo) return;

    // Highlight selected card
    document.querySelectorAll('.theme-card').forEach(card => card.classList.remove('active'));
    const selectedCard = document.querySelector(`.theme-card[data-theme="${themeNumber}"]`);
    if (selectedCard) selectedCard.classList.add('active');

    // Update display info
    const themeNameEl = document.getElementById('themeName');
    const themeDescriptionEl = document.getElementById('themeDescription');
    const selectedThemePanel = document.getElementById('selectedTheme');

    if (themeNameEl) themeNameEl.textContent = `${themeInfo.icon} ${themeInfo.name}`;
    if (themeDescriptionEl) themeDescriptionEl.textContent = themeInfo.description;
    if (selectedThemePanel) selectedThemePanel.style.display = 'block';

    // Scroll to display panel smoothly
    selectedThemePanel?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  // --- TEST THEME IN APP (LIVE PREVIEW) ---
  testThemeInApp(event) {
    if (event) event.preventDefault(); // Prevent redirect or form submit

    if (!this.themeValue) return alert("Please select a theme first!");
    const themeInfo = this.themes[this.themeValue];

    // Apply live
    this.applyTheme();

    alert(`✅ Theme "${themeInfo.name}" applied!\nIt will persist across page reloads.`);
  }

  // --- COPY THEME CSS ---
  copyThemeCode(event) {
    if (!this.themeValue) return alert("Please select a theme first!");

    const btn = event.currentTarget;
    const themeInfo = this.themes[this.themeValue];

    const themeCSS = `body.${themeInfo.class} { /* Add your theme CSS here */ }`;

    navigator.clipboard.writeText(themeCSS).then(() => {
      const originalText = btn.innerHTML;
      btn.innerHTML = '<i class="fas fa-check"></i> Copied!';
      btn.style.background = 'linear-gradient(135deg, #28a745 0%, #20c997 100%)';
      setTimeout(() => {
        btn.innerHTML = originalText;
        btn.style.background = 'linear-gradient(135deg, #0055A4 0%, #0066CC 100%)';
      }, 2000);
    }).catch(err => {
      console.error('Failed to copy: ', err);
      alert("Failed to copy to clipboard. Please try again.");
    });
  }
}
