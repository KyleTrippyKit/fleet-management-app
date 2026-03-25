class Current < ActiveSupport::CurrentAttributes
  attribute :user
  attribute :ip_address
  attribute :user_agent
  
  # Set request attributes
  def set_request(request)
    self.ip_address = request.remote_ip
    self.user_agent = request.user_agent
  end
  
  # Reset all attributes
  def reset
    self.user = nil
    self.ip_address = nil
    self.user_agent = nil
  end
end