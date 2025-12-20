require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module ActivePlusDemo
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Ignore lib subdirectories that do not contain `.rb` files.
    config.autoload_lib(ignore: %w[assets tasks])

    # Disable Action Cable if not used
    config.action_cable.mount_path = nil
    config.action_cable.url = nil
    config.action_cable.allowed_request_origins = []
    config.action_cable.disable_request_forgery_protection = true

    # Active Storage default service
    config.active_storage.service = ENV.fetch("ACTIVE_STORAGE_SERVICE", "local").to_sym
  end
end
