# app/models/audit_log.rb
class AuditLog < ApplicationRecord
  belongs_to :user
  belongs_to :auditable, polymorphic: true
  
  def self.log(user, action, resource, details = {})
    create!(
      user: user,
      action: action,
      auditable: resource,
      details: details,
      ip_address: Current.ip_address,
      user_agent: Current.user_agent
    )
  end
end