# config/importmap.rb
pin "application", preload: true

# Core Rails libraries
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true

# Chart.js from CDN (REMOVE .js extension from the pin name)
pin "chart.js", to: "https://ga.jspm.io/npm:chart.js@4.4.1/dist/chart.js"

# Remove these lines - they're causing the conflict:
# pin "chartkick", to: "chartkick.js"
# pin "Chart.bundle", to: "Chart.bundle.js"

# Your controllers
pin_all_from "app/javascript/controllers", under: "controllers"