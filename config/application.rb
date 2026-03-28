# config/application.rb
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
    
    # Active Job queue adapter
    config.active_job.queue_adapter = :sidekiq
    
    # Demo mode toggle
    config.x.demo_mode = Rails.env.development?
    
    # =====================================================
    # SIDEKIQ CRON SCHEDULE CONFIGURATION
    # =====================================================
    config.after_initialize do
      if defined?(Sidekiq) && Sidekiq.server?
        schedule_file = Rails.root.join("config", "sidekiq_schedule.yml")
        
        if File.exist?(schedule_file)
          begin
            # Load the schedule file
            schedule = YAML.load_file(schedule_file)
            
            # Schedule each job
            schedule.each do |job_name, job_config|
              # Skip if already scheduled
              next if Sidekiq::Cron::Job.find(job_name)
              
              # Create the cron job
              Sidekiq::Cron::Job.create(
                name: job_name,
                cron: job_config['cron'],
                class: job_config['class'],
                queue: job_config['queue'] || 'default',
                args: job_config['args'] || [],
                description: job_config['description'] || "Scheduled job: #{job_name}"
              )
            end
            
            Rails.logger.info "Sidekiq cron jobs loaded from #{schedule_file}"
          rescue => e
            Rails.logger.error "Failed to load Sidekiq cron schedule: #{e.message}"
          end
        end
      end
    end
  end
end