# frozen_string_literal: true

source "https://rubygems.org"

# =============================
# Rails
# =============================
# Edge Rails alternative (optional): gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.1"

# =============================
# Database
# =============================
gem "pg", "~> 1.1"         # PostgreSQL as DB
gem "tzinfo-data", platforms: %i[windows jruby] # Windows timezone support

# =============================
# Web Server
# =============================
gem "puma", ">= 5.0"       # Puma server

# =============================
# JavaScript & CSS
# =============================
gem "importmap-rails"      # ESM import maps for JS
gem "jsbundling-rails", "~> 1.3" # Optional for bundling JS via esbuild/webpack
gem "cssbundling-rails"    # CSS bundling
gem "bootstrap", "~> 5.3"  # CSS framework

# =============================
# Hotwire / Stimulus / Turbo
# =============================
gem "turbo-rails"
gem "stimulus-rails", "~> 1.3"

# =============================
# Authentication
# =============================
gem "devise"

# =============================
# API & JSON
# =============================
gem "jbuilder"
gem "groupdate"             # Optional: grouping by dates in queries

# =============================
# File / Image Handling
# =============================
gem "propshaft"             # Modern asset pipeline
gem "image_processing", "~> 1.2" # Active Storage variants

# =============================
# Caching, Queues, and Action Cable
# =============================
gem "solid_cache"           # Cache adapter
gem "solid_queue"           # Background job adapter
gem "solid_cable"           # Action Cable adapter

# =============================
# Utilities / Deployment
# =============================
gem "bootsnap", require: false # Speeds up boot times
gem "kamal", require: false     # Deploy anywhere as Docker container
gem "thruster", require: false  # HTTP caching/compression for Puma
gem "chartkick"                 # Charts

# =============================
# Development & Debugging
# =============================
group :development do
  gem "web-console"           # Console on exception pages
end

group :development, :test do
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "bundler-audit", require: false # Security audits
  gem "brakeman", require: false      # Static analysis for vulnerabilities
  gem "rubocop-rails-omakase", require: false # Ruby style linting
end

# =============================
# Testing
# =============================
group :test do
  gem "capybara"              # System tests
  gem "selenium-webdriver"
end

# =============================
# Optional: Active Model Passwords
# =============================
# gem "bcrypt", "~> 3.1.7"

gem 'kaminari'
