# app/models/quickbooks_integration.rb - COMPLETE REVISED VERSION
class QuickbooksIntegration < ApplicationRecord
  belongs_to :user, optional: true
  
  # Validations
  validates :company_id, uniqueness: true, allow_nil: true
  
  # Scopes
  scope :connected, -> { where(connected: true) }
  scope :auto_sync_enabled, -> { where(auto_sync: true, connected: true) }
  scope :needs_token_refresh, -> { 
    where(connected: true)
    .where('token_expires_at IS NULL OR token_expires_at < ?', 30.minutes.from_now)
  }
  
  # ========================
  # AGENCY INTEGRATION METHODS
  # ========================
  
  # Find or initialize integration for an agency
  def self.for_agency(agency_code)
    return new(agency_code: agency_code) unless table_exists?
    
    # Try to find by agency_code if column exists
    if column_exists?(:agency_code) && agency_code.present?
      where(agency_code: agency_code).first_or_initialize do |integration|
        integration.agency_code = agency_code
      end
    else
      # Fallback: find by user's agency or create default
      user = User.find_by(agency_code: agency_code) if User.column_exists?(:agency_code)
      if user
        where(user_id: user.id).first_or_initialize do |integration|
          integration.user_id = user.id
        end
      else
        new(agency_code: agency_code)
      end
    end
  rescue => e
    Rails.logger.error "Error in for_agency(#{agency_code}): #{e.message}"
    new(agency_code: agency_code)
  end
  
  # Check if an agency is connected
  def self.connected_for_agency?(agency_code)
    return false unless table_exists?
    
    if column_exists?(:agency_code) && agency_code.present?
      where(agency_code: agency_code, connected: true).exists?
    else
      # Check through users
      user_ids = User.where(agency_code: agency_code).pluck(:id) if User.column_exists?(:agency_code)
      where(user_id: user_ids, connected: true).exists? if user_ids.present?
    end
  rescue => e
    Rails.logger.error "Error checking connection for agency #{agency_code}: #{e.message}"
    false
  end
  
  # Get access token for agency
  def self.access_token_for_agency(agency_code)
    integration = for_agency(agency_code)
    integration.connected? ? integration.access_token : nil
  end
  
  # Get realm_id for agency
  def self.realm_id_for_agency(agency_code)
    integration = for_agency(agency_code)
    integration.connected? ? integration.realm_id : nil
  end
  
  # Agency code getter with fallback
  def agency_code
    # Check if column exists, otherwise return from user
    if self.class.column_exists?(:agency_code) && self[:agency_code].present?
      self[:agency_code]
    elsif user&.respond_to?(:agency_code) && user.agency_code.present?
      user.agency_code
    else
      'default'
    end
  end
  
  # Agency code setter
  def agency_code=(value)
    if self.class.column_exists?(:agency_code)
      self[:agency_code] = value
    end
  end
  
  # ========================
  # DATABASE SAFETY METHODS
  # ========================
  
  # Safely check if table exists
  def self.table_exists?
    ActiveRecord::Base.connection.table_exists?(table_name)
  rescue => e
    Rails.logger.warn "QuickbooksIntegration table check failed: #{e.message}"
    false
  end
  
  # Check if column exists
  def self.column_exists?(name)
    return false unless table_exists?
    
    @column_names ||= connection.columns(table_name).map(&:name)
    @column_names.include?(name.to_s)
  rescue => e
    Rails.logger.warn "Column check failed for #{name}: #{e.message}"
    false
  end
  
  # Global connection status
  def self.connected?
    return false unless table_exists?
    exists?(connected: true)
  rescue => e
    Rails.logger.warn "Connected check failed: #{e.message}"
    false
  end
  
  # Last sync timestamp
  def self.last_sync
    return nil unless table_exists?
    where(connected: true).maximum(:last_sync_at)
  rescue => e
    Rails.logger.warn "Last sync check failed: #{e.message}"
    nil
  end
  
  # Auto-sync status
  def self.auto_sync?
    return false unless table_exists?
    where(connected: true).exists?(auto_sync: true)
  rescue => e
    Rails.logger.warn "Auto-sync check failed: #{e.message}"
    false
  end
  
  # ========================
  # SYNC OPERATIONS
  # ========================
  
  # Sync a single invoice to QuickBooks
  def self.sync_invoice(invoice)
    return { success: false, error: "QuickBooks not connected" } unless connected?
    
    # Mock implementation - replace with actual QuickBooks API call
    begin
      # In production, you would:
      # 1. Create QuickBooks invoice object
      # 2. Post to QuickBooks API
      # 3. Update invoice with QuickBooks ID
      
      result = {
        success: true,
        quickbooks_id: "QB-INV-#{SecureRandom.hex(8)}",
        sync_date: Time.current,
        invoice_id: invoice.id
      }
      
      # Update the invoice
      if invoice.update(
        quickbooks_id: result[:quickbooks_id],
        last_sync_at: result[:sync_date],
        sync_status: 'success'
      )
        result
      else
        { success: false, error: "Failed to update invoice", errors: invoice.errors.full_messages }
      end
    rescue => e
      { success: false, error: "Sync failed: #{e.message}" }
    end
  end
  
  # Sync a transaction to QuickBooks
  def self.sync_transaction(transaction)
    return { success: false, error: "QuickBooks not connected" } unless connected?
    
    # Mock implementation
    begin
      result = {
        success: true,
        quickbooks_id: "QB-TXN-#{SecureRandom.hex(8)}",
        sync_date: Time.current,
        transaction_id: transaction.id
      }
      
      if transaction.update(
        quickbooks_id: result[:quickbooks_id],
        last_sync_at: result[:sync_date],
        sync_status: 'success'
      )
        result
      else
        { success: false, error: "Failed to update transaction", errors: transaction.errors.full_messages }
      end
    rescue => e
      { success: false, error: "Sync failed: #{e.message}" }
    end
  end
  
  # Sync all pending invoices
  def self.sync_all_pending_invoices
    return unless table_exists?
    
    results = { success: 0, failed: 0, errors: [] }
    
    Invoice.where(quickbooks_id: nil)
           .where.not(status: ['draft', 'cancelled'])
           .find_each(batch_size: 50) do |invoice|
      result = sync_invoice(invoice)
      if result[:success]
        results[:success] += 1
      else
        results[:failed] += 1
        results[:errors] << { invoice_id: invoice.id, error: result[:error] }
      end
    end
    
    results
  rescue => e
    Rails.logger.error "Batch invoice sync failed: #{e.message}"
    { success: 0, failed: 0, errors: [e.message] }
  end
  
  # Sync all pending transactions
  def self.sync_all_pending_transactions
    return unless table_exists?
    
    results = { success: 0, failed: 0, errors: [] }
    
    Transaction.where(quickbooks_id: nil, status: 'completed')
               .find_each(batch_size: 50) do |transaction|
      result = sync_transaction(transaction)
      if result[:success]
        results[:success] += 1
      else
        results[:failed] += 1
        results[:errors] << { transaction_id: transaction.id, error: result[:error] }
      end
    end
    
    results
  rescue => e
    Rails.logger.error "Batch transaction sync failed: #{e.message}"
    { success: 0, failed: 0, errors: [e.message] }
  end
  
  # Full sync of all pending data
  def self.sync_all_pending
    return unless table_exists?
    
    invoice_results = sync_all_pending_invoices
    transaction_results = sync_all_pending_transactions
    
    {
      invoices: invoice_results,
      transactions: transaction_results,
      total_success: invoice_results[:success] + transaction_results[:success],
      total_failed: invoice_results[:failed] + transaction_results[:failed]
    }
  end
  
  # ========================
  # TOKEN MANAGEMENT
  # ========================
  
  # Check if token is expired or about to expire
  def token_expired?
    return true unless token_expires_at
    token_expires_at <= 30.minutes.from_now
  end
  
  # Refresh access token (mock implementation)
  def refresh_token!
    return false unless connected? && refresh_token.present?
    
    # In production, you would call QuickBooks API to refresh the token
    update!(
      access_token: "refreshed_token_#{SecureRandom.hex(20)}",
      token_expires_at: 1.hour.from_now
    )
    
    true
  rescue => e
    Rails.logger.error "Token refresh failed: #{e.message}"
    false
  end
  
  # ========================
  # STATUS HELPERS
  # ========================
  
  # Check if QuickBooks is configured for the app
  def self.configured?
    return false unless table_exists?
    connected.any?
  rescue => e
    Rails.logger.warn "Configuration check failed: #{e.message}"
    false
  end
  
  # Initialize default settings
  def self.initialize_defaults
    return unless table_exists?
    
    # Create a default record if none exists
    unless exists?
      create!(
        company_id: 'default',
        connected: false,
        auto_sync: false,
        agency_code: 'default'
      )
    end
  rescue => e
    Rails.logger.error "Failed to initialize QuickBooks defaults: #{e.message}"
  end
  
  # Get connection status badge
  def connection_status_badge
    if connected?
      if token_expired?
        { label: "Connected (Token Expired)", color: "warning", icon: "exclamation-triangle" }
      else
        { label: "Connected", color: "success", icon: "check-circle" }
      end
    else
      { label: "Not Connected", color: "danger", icon: "x-circle" }
    end
  end
  
  # Get sync status badge
  def sync_status_badge
    case sync_status
    when 'success'
      { label: "Synced", color: "success", icon: "check-circle" }
    when 'failed'
      { label: "Sync Failed", color: "danger", icon: "x-circle" }
    when 'syncing'
      { label: "Syncing...", color: "info", icon: "arrow-repeat" }
    when 'pending'
      { label: "Pending Sync", color: "warning", icon: "clock" }
    else
      { label: "Unknown", color: "secondary", icon: "question-circle" }
    end
  end
  
  # Last sync time in words
  def last_sync_time_ago
    return "Never" unless last_sync_at
    "#{time_ago_in_words(last_sync_at)} ago"
  end
  
  # Token expiration time
  def token_expires_in
    return "Not set" unless token_expires_at
    if token_expired?
      "Expired"
    else
      distance_of_time_in_words(Time.current, token_expires_at)
    end
  end
  
  # ========================
  # MOCK DATA FOR DEVELOPMENT
  # ========================
  
  # Create mock connected integration for development
  def self.create_mock_connection(agency_code = 'demo')
    return unless Rails.env.development? || Rails.env.test?
    
    integration = for_agency(agency_code)
    integration.update!(
      connected: true,
      company_id: "company_#{agency_code.downcase}",
      realm_id: "mock_realm_#{SecureRandom.hex(10)}",
      access_token: "mock_token_#{SecureRandom.hex(20)}",
      refresh_token: "mock_refresh_#{SecureRandom.hex(20)}",
      token_expires_at: 1.hour.from_now,
      auto_sync: false,
      last_sync_at: Time.current,
      sync_status: 'success'
    )
    
    integration
  rescue => e
    Rails.logger.error "Failed to create mock connection: #{e.message}"
    nil
  end
  
  # ========================
  # INSTANCE METHODS
  # ========================
  
  # Check if ready for sync
  def ready_for_sync?
    connected? && !token_expired?
  end
  
  # Perform a sync operation
  def perform_sync(sync_type = :all)
    return { success: false, error: "Not connected" } unless connected?
    return { success: false, error: "Token expired" } if token_expired?
    
    case sync_type.to_sym
    when :invoices
      self.class.sync_all_pending_invoices
    when :transactions
      self.class.sync_all_pending_transactions
    when :all
      self.class.sync_all_pending
    else
      { success: false, error: "Unknown sync type: #{sync_type}" }
    end
  end
  
  # Disconnect from QuickBooks
  def disconnect!
    update!(
      connected: false,
      access_token: nil,
      refresh_token: nil,
      realm_id: nil,
      company_id: nil,
      token_expires_at: nil,
      sync_status: 'disconnected'
    )
  end
end