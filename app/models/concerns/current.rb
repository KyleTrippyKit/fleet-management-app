# app/models/concerns/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :user
  attribute :request
  attribute :agency
  attribute :pos_transaction
  
  # Fixed: Ensure user is not an array
  def self.set_request(request)
    self.request = request
    
    # Safely get the user - handle if it's an array
    user = if self.user.is_a?(Array)
             self.user.first
           else
             self.user
           end
    
    # Set agency if we have a valid user
    if user && user.respond_to?(:agency)
      self.agency = user.agency
    else
      self.agency = nil
    end
  end
  
  # Fixed: Handle array in with method
  def self.with(user, request = nil)
    # Ensure user is not an array
    actual_user = if user.is_a?(Array)
                    user.first
                  else
                    user
                  end
    
    self.user = actual_user
    self.request = request
    self.agency = actual_user&.agency
    
    yield
  ensure
    reset
  end
  
  # Reset all attributes
  def self.reset
    self.user = nil
    self.request = nil
    self.agency = nil
    self.pos_transaction = nil
  end
  
  # POS-specific helpers - with safe checks
  def self.pos_context
    {
      user: user.is_a?(User) ? user : nil,
      agency: agency,
      request: request
    }
  end
  
  # Check if POS is accessible - with safe check
  def self.can_access_pos?
    user.is_a?(User) && user.respond_to?(:can_access_pos?) ? user.can_access_pos? : false
  end
  
  # Get current agency code - with safe check
  def self.agency_code
    if agency && agency.respond_to?(:code)
      agency.code
    elsif user.is_a?(User) && user.respond_to?(:agency_code)
      user.agency_code
    else
      nil
    end
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
  
  # Create audit trail for actions - with safe checks
  def self.audit(action, resource, details = {})
    # Ensure user is a User object
    return unless user.is_a?(User) && resource
    
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
  
  # PTSC-specific methods with safe checks
  def self.ptsc_routes
    return [] unless is_ptsc? && agency && agency.respond_to?(:id)
    Route.where(agency: agency).pluck(:route_code, :name)
  rescue
    []
  end
  
  def self.ptsc_fare_classes
    return [] unless is_ptsc?
    ['adult', 'child', 'student', 'senior', 'disabled']
  end
  
  def self.ptsc_ticket_types
    return [] unless is_ptsc?
    ['single', 'daily', 'weekly', 'monthly', 'season']
  end
  
  # Get fare for route and class with safe checks
  def self.get_fare(route_code, fare_class)
    return nil unless agency && agency.respond_to?(:id) && route_code && fare_class
    FareRule.find_by(agency: agency, route_code: route_code, fare_class: fare_class)&.amount
  rescue
    nil
  end
  
  # Validate PTSC transaction with safe checks
  def self.validate_ptsc_transaction(params)
    return { valid: false, error: "Not in PTSC context" } unless is_ptsc?
    
    errors = []
    
    # Check route with safe check
    begin
      unless Route.exists?(agency: agency, route_code: params[:route_code])
        errors << "Invalid route: #{params[:route_code]}"
      end
    rescue
      errors << "Route validation failed"
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