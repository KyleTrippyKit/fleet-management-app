# Pin application entry point
pin "application", preload: true

# Core Rails libraries
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true

# Chart.js and date adapter
pin "chart.js", to: "chart.js" # @4.5.1
pin "chartjs-adapter-date-fns", to: "chartjs-adapter-date-fns.js" # @3.0.0
pin "date-fns", to: "date-fns.js" # @4.1.0
pin "@kurkle/color", to: "@kurkle--color.js" # @0.3.4

# Pin all controllers from app/javascript/controllers
pin_all_from "app/javascript/controllers", under: "controllers"