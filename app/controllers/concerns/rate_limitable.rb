# app/controllers/concerns/rate_limitable.rb
module RateLimitable
  extend ActiveSupport::Concern
  
  def check_rate_limit(limit = 100, period = 1.hour)
    key = "rate_limit:#{current_user.id}:#{action_name}"
    count = Rails.cache.increment(key, 1, expires_in: period)
    
    if count > limit
      render json: { error: "Rate limit exceeded" }, status: :too_many_requests
      return false
    end
    true
  end
end