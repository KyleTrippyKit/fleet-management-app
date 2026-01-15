# app/models/transaction.rb - COMPLETE REVISED WITH QUICKBOOKS SUPPORT
class Transaction < ApplicationRecord
  belongs_to :invoice, optional: true
  belongs_to :vehicle, optional: true
  belongs_to :user
  
  # Add this association
  has_one :payment_history, foreign_key: "payment_transaction_id", dependent: :nullify
  
  # Status enums
  enum :status, {
    pending: 0,
    completed: 1,
    failed: 2,
    voided: 3,
    refunded: 4
  }, default: :pending
  
  enum :transaction_type, {
    payment: 0,
    refund: 1,
    adjustment: 2,
    deposit: 3
  }, default: :payment
  
  # Sync status enum - IMPORTANT: Match database constraint values exactly
  enum :sync_status, {
    pending: 'pending',
    syncing: 'syncing',
    success: 'success',
    failed: 'failed',
    error: 'error'
  }, default: 'pending', prefix: :sync
  
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :reference_number, uniqueness: true, allow_blank: true
  
  # Scopes
  scope :completed, -> { where(status: :completed) }
  scope :this_month, -> { where(created_at: Time.current.beginning_of_month..Time.current.end_of_month) }
  scope :for_invoice, ->(invoice_id) { where(invoice_id: invoice_id) }
  
  # QuickBooks sync scopes
  scope :with_quickbooks, -> { where.not(quickbooks_id: nil) }
  scope :without_quickbooks, -> { where(quickbooks_id: nil) }
  scope :recently_synced, ->(hours = 24) { 
    where.not(last_sync_at: nil).where('last_sync_at > ?', hours.hours.ago) 
  }
  scope :sync_successful, -> { where(sync_status: 'success') }
  scope :sync_failed, -> { where(sync_status: ['failed', 'error']) }
  scope :pending_sync, -> { where(sync_status: 'pending') }
  scope :syncing, -> { where(sync_status: 'syncing') }
  
  before_create :generate_reference_number
  
  def generate_reference_number
    self.reference_number ||= "TXN-#{Time.now.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
  end
  
  # Update this method to also create payment history
  def self.record_payment(params)
    transaction = nil
    
    ActiveRecord::Base.transaction do
      transaction = new(params)
      transaction.status = :completed
      transaction.transaction_type = :payment
      transaction.save!
      
      # Create payment history if invoice is provided
      if transaction.invoice_id
        PaymentHistory.create_from_transaction(transaction, transaction.invoice_id)
      end
    end
    
    transaction
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Failed to record payment: #{e.message}"
    nil
  end
  
  # QuickBooks sync methods
  def quickbooks_synced?
    quickbooks_id.present?
  end
  
  def recently_synced?(hours = 24)
    last_sync_at.present? && last_sync_at > hours.hours.ago
  end
  
  def sync_stale?
    last_sync_at.present? && last_sync_at < 7.days.ago
  end
  
  def sync_time_ago
    return "Never synced" unless last_sync_at
    "#{time_ago_in_words(last_sync_at)} ago"
  end
  
  def sync_status_badge
    # Return early if not synced at all
    return { label: "Not Synced", color: "secondary", icon: "clock-history" } unless quickbooks_synced?
    
    case sync_status
    when 'success'
      if recently_synced?(1)
        { label: "Recently Synced", color: "success", icon: "check-circle-fill" }
      elsif recently_synced?(24)
        { label: "Synced Today", color: "info", icon: "check-circle" }
      elsif recently_synced?(168)
        { label: "Synced This Week", color: "warning", icon: "clock" }
      else
        { label: "Sync Stale", color: "secondary", icon: "exclamation-triangle" }
      end
    when 'failed'
      { label: "Sync Failed", color: "danger", icon: "x-circle" }
    when 'error'
      { label: "Sync Error", color: "danger", icon: "exclamation-triangle-fill" }
    when 'syncing'
      { label: "Syncing...", color: "info", icon: "arrow-repeat" }
    when 'pending'
      { label: "Pending Sync", color: "warning", icon: "clock-history" }
    else
      { label: "Unknown", color: "secondary", icon: "question-circle" }
    end
  end
  
  # QuickBooks sync
  def sync_to_quickbooks
    return { success: true, message: 'Already synced' } if quickbooks_id.present?
    
    # Update status to syncing
    update!(sync_status: 'syncing')
    
    # Get QuickBooks integration for this transaction's agency
    agency = invoice&.vehicle&.agency
    if agency.nil?
      update!(sync_status: 'failed', sync_error: 'No agency assigned')
      return { success: false, error: 'No agency assigned' }
    end
    
    quickbooks_integration = QuickbooksIntegration.for_agency(agency.code)
    unless quickbooks_integration&.connected?
      update!(sync_status: 'failed', sync_error: 'QuickBooks not connected for this agency')
      return { success: false, error: 'QuickBooks not connected for this agency' }
    end
    
    begin
      # Mock sync - replace with real QuickBooks API call
      # In production, you would call: quickbooks_integration.create_payment(self)
      result = {
        success: true,
        quickbooks_id: "QB-TXN-#{SecureRandom.hex(8)}",
        sync_date: Time.current
      }
      
      if result[:success]
        update!(
          quickbooks_id: result[:quickbooks_id],
          last_sync_at: result[:sync_date] || Time.current,
          sync_status: 'success',
          sync_error: nil
        )
        { success: true, message: 'Synced successfully', quickbooks_id: result[:quickbooks_id] }
      else
        update!(
          sync_status: 'failed',
          sync_error: result[:error],
          last_sync_at: nil
        )
        { success: false, error: result[:error] }
      end
    rescue => e
      update!(
        sync_status: 'error',
        sync_error: e.message,
        last_sync_at: nil
      )
      { success: false, error: "QuickBooks sync error: #{e.message}" }
    end
  end
  
  # Batch sync method for multiple transactions
  def self.batch_sync_to_quickbooks(transaction_ids)
    transactions = where(id: transaction_ids, sync_status: ['pending', 'failed', 'error'])
    results = { success: 0, failed: 0, errors: [] }
    
    transactions.each do |transaction|
      result = transaction.sync_to_quickbooks
      if result[:success]
        results[:success] += 1
      else
        results[:failed] += 1
        results[:errors] << { transaction_id: transaction.id, error: result[:error] }
      end
    end
    
    results
  end
  
  # Check if transaction has a payment history
  def has_payment_history?
    payment_history.present?
  end
  
  # Get agency through invoice -> vehicle
  def agency
    invoice&.vehicle&.agency
  end
  
  # Get agency code
  def agency_code
    agency&.code || invoice&.vehicle&.service_owner
  end
  
  # Sync timeline
  def sync_timeline
    timeline = []
    
    timeline << { event: 'Created', date: created_at, description: "Transaction created" }
    
    if quickbooks_id
      timeline << { 
        event: 'QuickBooks ID Assigned', 
        date: updated_at, 
        description: "Assigned QuickBooks ID: #{quickbooks_id}" 
      }
    end
    
    if last_sync_at
      timeline << { 
        event: 'QuickBooks Sync', 
        date: last_sync_at, 
        description: "Synced with QuickBooks" 
      }
    end
    
    timeline.sort_by { |event| event[:date] }.reverse
  end
  
  # Helper method to sync if conditions are met
  def sync_if_needed
    return if quickbooks_synced? && recently_synced?(1)
    sync_to_quickbooks
  end
  
  # Display methods
  def display_status
    status.humanize
  end
  
  def display_transaction_type
    transaction_type.humanize
  end
  
  def display_amount
    ActionController::Base.helpers.number_to_currency(amount)
  end
  
  # Validation for QuickBooks sync
  def ready_for_sync?
    return false unless status == 'completed'
    return false unless amount.present? && amount > 0
    return false unless reference_number.present?
    true
  end
  
  # Reset sync (useful for testing)
  def reset_sync
    update!(
      quickbooks_id: nil,
      last_sync_at: nil,
      sync_status: 'pending',
      sync_error: nil
    )
  end
end