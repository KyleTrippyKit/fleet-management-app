# app/models/audit_log.rb
class AuditLog < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :record, polymorphic: true, 
             foreign_type: 'record_type', 
             foreign_key: 'record_id'
  
  # Custom log method that matches your table structure
  def self.log(user, action, resource, details = {})
    create!(
      user: user,
      action: action,
      record: resource,  # This will set record_type and record_id
      audit_changes: details.to_json,
      ip_address: Current.ip_address,
      note: nil
    )
  end
  
  def audit_changes_data
    return {} unless audit_changes.present?
    JSON.parse(audit_changes)
  rescue JSON::ParserError
    {}
  end
end