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
