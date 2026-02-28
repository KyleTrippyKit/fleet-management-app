# Pin application entry point
pin "application", preload: true

# Core Rails libraries
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true

# Pin all controllers (this creates the "controllers" entry)
pin_all_from "app/javascript/controllers", under: "controllers"

# Pin all channels for Action Cable
pin_all_from "app/javascript/channels", under: "channels"

# Pin Action Cable
pin "@rails/actioncable", to: "actioncable.esm.js", preload: true

# ✅ Temporarily DISABLE polish while testing Stimulus start-up
# (we will re-enable this after we confirm window.Stimulus exists)
pin "polish", to: "polish.js", preload: true

# External dependencies
pin "@nathanvda/cocoon", to: "@nathanvda--cocoon.js"
pin "jquery", to: "jquery.js"

# Chart libraries
pin "chartkick", to: "https://ga.jspm.io/npm:chartkick@5.0.1/dist/chartkick.esm.js"
pin "chart.js", to: "https://ga.jspm.io/npm:chart.js@4.5.1/dist/chart.umd.js"