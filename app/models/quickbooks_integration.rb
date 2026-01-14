# app/models/quickbooks_integration.rb
class QuickbooksIntegration < ApplicationRecord
  belongs_to :user, optional: true
  
  validates :company_id, presence: true
  
  scope :connected, -> { where(connected: true) }
  
  # Safely check if table exists before querying
  def self.table_exists?
    ActiveRecord::Base.connection.table_exists?(:quickbooks_integrations)
  rescue
    false
  end
  
  def self.connected?
    return false unless table_exists?
    exists?(connected: true)
  rescue ActiveRecord::StatementInvalid, PG::UndefinedTable
    false
  end
  
  def self.last_sync
    return nil unless table_exists?
    where(connected: true).maximum(:last_sync_at)
  rescue ActiveRecord::StatementInvalid, PG::UndefinedTable
    nil
  end
  
  def self.auto_sync?
    return false unless table_exists?
    where(connected: true).exists?(auto_sync: true)
  rescue ActiveRecord::StatementInvalid, PG::UndefinedTable
    false
  end
  
  def self.sync_invoice(invoice)
    # This would contain the actual QuickBooks API integration logic
    # For now, return a mock response
    {
      success: true,
      quickbooks_id: "QB-#{SecureRandom.hex(8)}",
      sync_date: Time.current
    }
  end
  
  def self.sync_all_pending
    return unless table_exists?
    
    Invoice.where.not(quickbooks_id: nil).where(status: ['pending', 'overdue']).find_each do |invoice|
      sync_invoice(invoice)
    end
  end
  
  # Helper method to check if QuickBooks is configured
  def self.configured?
    table_exists? && exists?
  end
  
  # Initialize default settings if needed
  def self.initialize_defaults
    return unless table_exists?
    
    # Create a default record if none exists
    unless exists?
      create!(
        company_id: 'default',
        connected: false,
        auto_sync: false
      )
    end
  rescue => e
    Rails.logger.error "Failed to initialize QuickBooks defaults: #{e.message}"
  end
  
  # ADD THESE NEW METHODS FOR AGENCY-SPECIFIC OPERATIONS:
  def self.for_agency(agency_code)
    where(agency_code: agency_code).first_or_initialize
  end
  
  def self.access_token_for_agency(agency_code)
    for_agency(agency_code).access_token
  end
  
  def self.realm_id_for_agency(agency_code)
    for_agency(agency_code).realm_id
  end
  
  def self.connected_for_agency?(agency_code)
    where(agency_code: agency_code, connected: true).exists?
  end
end