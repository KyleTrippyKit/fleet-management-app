// Import Rails UJS, Turbo, and Stimulus
import "@hotwired/turbo-rails"
import "./controllers"
import "@rails/ujs"
import "chartkick/chart.js"
import Chart from "chart.js/auto"

// Redraw Chartkick charts on Turbo load
document.addEventListener("turbo:load", () => {
  if (window.Chartkick) {
    Chartkick.eachChart(chart => chart.redraw())
  }
})

// Optional: you can also redraw when a turbo frame updates
document.addEventListener("turbo:frame-load", (event) => {
  if (window.Chartkick) {
    Chartkick.eachChart(chart => chart.redraw())
  }
})
