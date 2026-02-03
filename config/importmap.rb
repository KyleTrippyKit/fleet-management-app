# config/importmap.rb

# Pin application entry point
pin "application", preload: true

# Core Rails libraries
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true

# Pin all controllers from app/javascript/controllers
pin_all_from "app/javascript/controllers", under: "controllers"

# External dependencies
pin "@nathanvda/cocoon", to: "@nathanvda--cocoon.js"
pin "jquery", to: "jquery.js"

# Add Bootstrap - Use the bundle version (includes Popper)

# FIXED: Chart libraries - REMOVE Chart.bundle, keep only chart.js
pin "chartkick", to: "https://ga.jspm.io/npm:chartkick@5.0.1/dist/chartkick.esm.js"
pin "chart.js", to: "https://ga.jspm.io/npm:chart.js@4.5.1/dist/chart.umd.js"

