source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.3.10"

# Rails
gem "rails", "~> 8.1.1"

# Database
gem "sqlite3", "~> 2.8", group: [:development, :test]
gem "pg", "~> 1.6", group: :production

# Server
gem "puma", ">= 5.0"

# Boot speed optimization
gem "bootsnap", require: false

# JavaScript/CSS
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "sassc-rails"

# App gems
gem "devise", "~> 4.9"
gem "kaminari"
gem "activerecord-import"

# Error tracking
gem 'sentry-ruby'
gem 'sentry-rails'
gem 'sentry-sidekiq'

group :development, :test do
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem 'dotenv-rails', groups: [:development, :test]
end

group :development do
  gem "web-console"
  gem 'bullet'
end

gem 'bootstrap', '~> 5.3'
gem 'jquery-rails'
gem 'popper_js', '~> 2.0'
gem 'chartkick'
gem 'groupdate'
gem "image_processing", "~> 1.2"
gem 'vips'  # Faster than ImageMagick
gem "activestorage", "~> 8.1"

# For PDF export
gem 'wicked_pdf'
gem 'wkhtmltopdf-binary'  # Binary for PDF generation

gem 'faker'
gem "aws-sdk-s3", require: false

# JavaScript compressor
gem 'terser', '~> 1.2'

# Excel export
gem 'caxlsx'
gem 'caxlsx_rails'

gem 'cocoon'
gem "pundit", "~> 2.5"
gem 'sidekiq'
gem 'sidekiq-cron', '~> 1.12'
gem 'ransack'
gem "csv"
gem "redis", "~> 5.0"  # Required for Action Cable in production
gem "whenever", require: false
gem 'letter_opener'

# Testing gems
group :test do
  gem "minitest"
  gem "minitest-rails"
  gem "minitest-reporters"
  gem "rails-controller-testing"
  gem "capybara"
  gem "selenium-webdriver"
  gem "webdrivers"
  gem 'twilio-ruby'
  gem "stripe"
end