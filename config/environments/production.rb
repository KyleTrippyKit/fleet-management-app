require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  # Serve precompiled assets
  config.public_file_server.enabled = true
  config.public_file_server.headers = { 
    "cache-control" => "public, max-age=#{1.year.to_i}"
  }

  # Asset pipeline configuration
  config.assets.compile = false  # Don't compile on the fly
  config.assets.digest = true    # Add fingerprint to assets
  config.assets.css_compressor = :sass
  config.assets.js_compressor = :terser
  config.assets.gzip = true
  
  # Precompile additional assets
  config.assets.precompile += %w(application.js application.css *.png *.jpg *.jpeg *.gif *.svg *.ico)

  # Active Storage configuration
  config.active_storage.service = :local
  config.active_storage.service_urls_expire_in = 1.hour
  config.active_storage.variant_processor = :vips  # Use vips for processing
  
  # Serve images through the app, not as static files
  config.active_storage.resolve_model_to_route = :rails_storage_proxy_url
  
  # Asset host (important for Render.com CDN)
  # Uncomment and update for Render:
  # config.asset_host = "https://#{ENV['RENDER_EXTERNAL_HOSTNAME']}" if ENV['RENDER_EXTERNAL_HOSTNAME'].present?
  # config.active_storage.service_urls_expire_in = 7.days

  # Force SSL (enable on Render)
  config.force_ssl = ENV['RAILS_FORCE_SSL'].present?

  # Logging
  config.log_tags = [:request_id]
  config.logger = ActiveSupport::Logger.new(STDOUT)
  config.logger.formatter = ::Logger::Formatter.new
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health check logs
  config.silence_healthcheck_path = "/up"

  # Cache
  config.cache_store = :memory_store, { size: 64.megabytes }

  # Mailer
  config.action_mailer.default_url_options = { 
    host: ENV.fetch('APP_HOST', 'localhost:3000') 
  }
  config.action_mailer.raise_delivery_errors = false

  # I18n
  config.i18n.fallbacks = true

  # Active Record
  config.active_record.dump_schema_after_migration = false

  # Don't log asset requests
  config.assets.quiet = true
end