# config/importmap.rb

# Pin application entry point
pin "application", preload: true

# Core Rails libraries
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true

# Remove Chart.js from importmap - we'll load it manually only when needed
# pin "chart.js", to: "https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.js"
# pin "@kurkle/color", to: "https://cdn.jsdelivr.net/npm/@kurkle/color@0.3.2/dist/color.esm.js"

# Pin all controllers from app/javascript/controllers
pin_all_from "app/javascript/controllers", under: "controllers"