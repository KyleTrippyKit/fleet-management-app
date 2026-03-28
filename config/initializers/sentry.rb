# config/initializers/sentry.rb
Sentry.init do |config|
  config.dsn = ENV['SENTRY_DSN']
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]
  config.traces_sample_rate = 0.5
  config.environment = Rails.env
  
  # Add user context
  config.before_send = lambda do |event, hint|
    if Current.user
      event.user = {
        id: Current.user.id,
        email: Current.user.email,
        role: Current.user.role
      }
    end
    event
  end
end