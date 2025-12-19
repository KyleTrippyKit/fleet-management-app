require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Asset server (optional)
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on local disk
  config.active_storage.service = :local

  # Force SSL (optional)
  # config.force_ssl = true

  # Log to STDOUT with request ID
  config.log_tags = [:request_id]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health check logs
  config.silence_healthcheck_path = "/up"

  # Deprecations
  config.active_support.report_deprecations = false

  # Use default cache store (no solid_cache_store)
  # config.cache_store = :memory_store

  # Active Job defaults (remove solid_queue)
  # config.active_job.queue_adapter = :async

  # Mailer
  config.action_mailer.default_url_options = { host: "example.com" }
  # config.action_mailer.raise_delivery_errors = false

  # I18n fallbacks
  config.i18n.fallbacks = true

  # Schema dump
  config.active_record.dump_schema_after_migration = false
  config.active_record.attributes_for_inspect = [:id]

  # Action Cable
  config.action_cable.disable_request_forgery_protection = true
  config.action_cable.allowed_request_origins = []
  config.action_cable.mount_path = nil
end
