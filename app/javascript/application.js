// app/javascript/application.js
console.log("🚀 Application starting (Importmap)");

// Turbo (Importmap)
import "@hotwired/turbo-rails";

// Stimulus controllers (auto-loaded)
import "./controllers";

// Chartkick & Chart.js are provided via importmap pins
// Available globally as window.Chartkick / window.Chart

// Redraw Chartkick charts on Turbo page load
document.addEventListener("turbo:load", () => {
  if (window.Chartkick) {
    Chartkick.eachChart(chart => chart.redraw());
  }
});

// Redraw charts when Turbo Frames update
document.addEventListener("turbo:frame-load", () => {
  if (window.Chartkick) {
    Chartkick.eachChart(chart => chart.redraw());
  }
});

console.log("✅ Application JS loaded");
