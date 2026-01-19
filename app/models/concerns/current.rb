# app/models/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :user
  attribute :request
  attribute :agency
  attribute :pos_transaction
  
  # Set current request
  def self.set_request(request)
    self.request = request
    self.agency = user&.agency if user
  end
  
  # Reset all attributes
  def self.reset
    self.user = nil
    self.request = nil
    self.agency = nil
    self.pos_transaction = nil
  end
  
  # Wrap execution with user context
  def self.with(user, request = nil)
    self.user = user
    self.request = request
    self.agency = user&.agency
    
    yield
  ensure
    reset
  end
  
  # POS-specific helpers
  def self.pos_context
    {
      user: user,
      agency: agency,
      request: request
    }
  end
  
  # Check if POS is accessible
  def self.can_access_pos?
    user&.can_access_pos?
  end
  
  # Check if user can open register
  def self.can_open_register?
    user&.can_open_register?
  end
  
  # Check if user can void transactions
  def self.can_void_transactions?
    user&.can_void_transactions?
  end
  
  # Check if user can refund transactions
  def self.can_refund_transactions?
    user&.can_refund_transactions?
  end
  
  # Get current agency code
  def self.agency_code
    agency&.code || user&.agency_code
  end
  
  # Check if current agency is PTSC
  def self.is_ptsc?
    agency_code == 'PTSC'
  end
  
  # Get IP address from request
  def self.ip_address
    request&.remote_ip if request
  end
  
  # Get user agent from request
  def self.user_agent
    request&.user_agent if request
  end
  
  # Create audit trail for actions
  def self.audit(action, resource, details = {})
    return unless user && resource
    
    audit_details = {
      action: action,
      user_id: user.id,
      user_email: user.email,
      resource_type: resource.class.name,
      resource_id: resource.id,
      ip_address: ip_address,
      user_agent: user_agent,
      timestamp: Time.current,
      details: details
    }
    
    # Log to database if AuditLog model exists
    if defined?(AuditLog)
      AuditLog.create(
        user: user,
        action: action.to_s,
        resource: resource,
        details: details.merge(audit_details),
        ip_address: ip_address,
        user_agent: user_agent
      )
    end
    
    # Also log to Rails logger for debugging
    Rails.logger.info("[AUDIT] #{action} by #{user.email} on #{resource.class.name}##{resource.id}")
  end
  
  # PTSC-specific methods
  def self.ptsc_routes
    return [] unless is_ptsc? && agency
    Route.where(agency: agency).pluck(:route_code, :name)
  end
  
  def self.ptsc_fare_classes
    return [] unless is_ptsc?
    ['adult', 'child', 'student', 'senior', 'disabled']
  end
  
  def self.ptsc_ticket_types
    return [] unless is_ptsc?
    ['single', 'daily', 'weekly', 'monthly', 'season']
  end
  
  # Get fare for route and class
  def self.get_fare(route_code, fare_class)
    return nil unless agency && route_code && fare_class
    FareRule.find_by(agency: agency, route_code: route_code, fare_class: fare_class)&.amount
  end
  
  # Validate PTSC transaction
  def self.validate_ptsc_transaction(params)
    return { valid: false, error: "Not in PTSC context" } unless is_ptsc?
    
    errors = []
    
    # Check route
    unless Route.exists?(agency: agency, route_code: params[:route_code])
      errors << "Invalid route: #{params[:route_code]}"
    end
    
    # Check fare class
    unless ptsc_fare_classes.include?(params[:fare_class])
      errors << "Invalid fare class: #{params[:fare_class]}"
    end
    
    # Check ticket type
    unless ptsc_ticket_types.include?(params[:ticket_type])
      errors << "Invalid ticket type: #{params[:ticket_type]}"
    end
    
    # Check passenger count
    if params[:passenger_count].to_i < 1
      errors << "Passenger count must be at least 1"
    end
    
    if errors.empty?
      { valid: true }
    else
      { valid: false, errors: errors }
    end
  end
end