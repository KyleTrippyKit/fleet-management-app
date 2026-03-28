# Pin application
pin "application", preload: true

# Core libraries
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true

# Pin all controllers
pin_all_from "app/javascript/controllers", under: "controllers"
