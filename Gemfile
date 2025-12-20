source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.3.10"

# Rails
gem "rails", "~> 8.1.1"

# Database
gem "sqlite3", "~> 2.8", group: [:development, :test]
gem "pg", "~> 1.5", group: :production

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
