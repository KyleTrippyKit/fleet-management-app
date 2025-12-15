# config/importmap.rb

# Application entrypoint
pin "application"

# Hotwired Rails libraries
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"

# Pin all controllers
pin_all_from "app/javascript/controllers", under: "controllers"

# Bootstrap
pin "bootstrap", to: "https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js"

# Charting (optional, if used)
pin "chartkick", to: "chartkick.js"
pin "chart.js", to: "https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"
