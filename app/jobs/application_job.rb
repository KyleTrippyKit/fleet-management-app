class ApplicationJob < ActiveJob::Base
  # For testing, run jobs immediately
  if Rails.env.test? || Rails.env.development?
    self.queue_adapter = :inline
  end
end
