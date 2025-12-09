# config/importmap.rb

# Application entrypoint
pin "application"

# Hotwired Rails libraries
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# Bootstrap JS
pin "bootstrap", to: "https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js"

# Chart.js and dependencies
pin "chart.js", to: "https://cdn.jsdelivr.net/npm/chart.js"

# Chartkick
pin "chartkick", to: "https://ga.jspm.io/npm:chartkick@5.0.2/dist/chartkick.mjs"