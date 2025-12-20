require_relative "development"

Rails.application.configure do
  # Use the local service for Active Storage
  config.active_storage.service = :local
end
