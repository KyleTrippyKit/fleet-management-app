source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.3.10"

# Rails
gem "rails", "~> 8.1.2"

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

group :development, :test do
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem 'dotenv-rails', groups: [:development, :test]
end

group :development do
  gem "web-console"
end

gem 'bootstrap', '~> 5.3'
gem 'jquery-rails'
gem 'popper_js', '~> 2.0'
gem 'chartkick'
gem 'groupdate'
gem "image_processing", "~> 1.2"
gem 'vips'  # Faster than ImageMagick
gem "activestorage", "~> 8.1"
gem 'bullet', group: :development
# For PDF export (optional)
# gem 'prawn'
# gem 'prawn-table'

# Or for HTML to PDF
gem 'wicked_pdf'
gem 'wkhtmltopdf-binary'  # Binary for PDF generation

gem 'faker'
gem "aws-sdk-s3", require: false
# JavaScript compressor
gem 'terser', '~> 1.2'

gem 'caxlsx'

# Replace old axlsx with modern caxlsx
gem 'caxlsx'
gem 'caxlsx_rails'

gem 'cocoon'
gem "pundit", "~> 2.5"
gem 'sidekiq'
gem 'dotenv-rails', groups: [:development, :test]
gem 'axlsx'
gem 'axlsx_rails'
gem "ransack"
gem "csv"
gem "redis", "~> 5.0"  # Required for Action Cable in production
gem 'whenever', require: false