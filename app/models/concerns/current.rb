# app/models/concerns/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :user
  attribute :request
  attribute :agency
  attribute :pos_transaction
  
  def self.set_request(request)
    self.request = request
    
    user = if self.user.is_a?(Array)
             self.user.first
           else
             self.user
           end
    
    if user && user.respond_to?(:agency)
      self.agency = user.agency
    else
      self.agency = nil
    end
  end
  
  def self.with(user, request = nil)
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
  
  def self.reset
    self.user = nil
    self.request = nil
    self.agency = nil
    self.pos_transaction = nil
  end
  
  def self.pos_context
    {
      user: user.is_a?(User) ? user : nil,
      agency: agency,
      request: request
    }
  end
  
  def self.can_access_pos?
    user.is_a?(User) && user.respond_to?(:can_access_pos?) ? user.can_access_pos? : false
  end
  
  def self.agency_code
    if agency && agency.respond_to?(:code)
      agency.code
    elsif user.is_a?(User) && user.respond_to?(:agency_code)
      user.agency_code
    else
      nil
    end
  end
  
  def self.is_ptsc?
    agency_code == 'PTSC'
  end
  
  def self.ip_address
    request&.remote_ip if request
  end
  
  def self.user_agent
    request&.user_agent if request
  end
  
  def self.audit(action, resource, details = {})
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
    
    Rails.logger.info("[AUDIT] #{action} by #{user.email} on #{resource.class.name}##{resource.id}")
  end
  
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
  
  def self.get_fare(route_code, fare_class)
    return nil unless agency && agency.respond_to?(:id) && route_code && fare_class
    FareRule.find_by(agency: agency, route_code: route_code, fare_class: fare_class)&.amount
  rescue
    nil
  end
  
  def self.validate_ptsc_transaction(params)
    return { valid: false, error: "Not in PTSC context" } unless is_ptsc?
    
    errors = []
    
    begin
      unless Route.exists?(agency: agency, route_code: params[:route_code])
        errors << "Invalid route: #{params[:route_code]}"
      end
    rescue
      errors << "Route validation failed"
    end
    
    unless ptsc_fare_classes.include?(params[:fare_class])
      errors << "Invalid fare class: #{params[:fare_class]}"
    end
    
    unless ptsc_ticket_types.include?(params[:ticket_type])
      errors << "Invalid ticket type: #{params[:ticket_type]}"
    end
    
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