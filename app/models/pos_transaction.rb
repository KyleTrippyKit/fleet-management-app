class PosTransaction < ApplicationRecord
  belongs_to :agency
  belongs_to :invoice, optional: true
  belongs_to :vehicle, optional: true
  belongs_to :user, optional: true
  belongs_to :cashier_session, optional: true
  
  enum :status, {
    pending: 0,
    completed: 1,
    voided: 2,
    refunded: 3
  }, default: :pending
  
  enum :payment_type, {
    cash: 0,
    card: 1,
    mobile_money: 2,
    bank_transfer: 3,
    credit: 4
  }, default: :cash
  
  # Validations
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :transaction_id, presence: true, uniqueness: true
  validates :receipt_number, presence: true, uniqueness: { scope: :agency_id }
  validates :passenger_count, numericality: { greater_than: 0 }, allow_nil: true
  
  # Callbacks
  before_validation :generate_transaction_id, on: :create
  before_validation :generate_receipt_number, on: :create
  before_validation :set_agency_from_user, on: :create
  before_validation :calculate_amount, if: -> { unit_fare.present? && passenger_count.present? }
  before_save :update_cashier_session_totals, if: :cashier_session_id_changed?
  after_save :log_status_change, if: :saved_change_to_status?
  
  # AGENCY SCOPES
  scope :by_agency, ->(agency_id) { where(agency_id: agency_id) }
  scope :by_agency_code, ->(code) { joins(:agency).where(agencies: { code: code.upcase }) }
  
  # Status scopes
  scope :completed, -> { where(status: :completed) }
  scope :today, -> { where(created_at: Time.current.beginning_of_day..Time.current.end_of_day) }
  scope :voided, -> { where(status: :voided) }
  scope :refunded, -> { where(status: :refunded) }
  
  # PTSC-specific scopes
  scope :by_route, ->(route_code) { where(route_code: route_code) }
  scope :by_fare_class, ->(fare_class) { where(fare_class: fare_class) }
  scope :by_ticket_type, ->(ticket_type) { where(ticket_type: ticket_type) }
  scope :return_trips, -> { where(is_return_trip: true) }
  scope :single_trips, -> { where(is_return_trip: false) }
  
  # Time-based scopes
  scope :this_week, -> { where(created_at: Date.today.beginning_of_week..Date.today.end_of_week) }
  scope :this_month, -> { where(created_at: Date.today.beginning_of_month..Date.today.end_of_month) }
  scope :last_7_days, -> { where(created_at: 7.days.ago.beginning_of_day..Time.current.end_of_day) }
  scope :last_30_days, -> { where(created_at: 30.days.ago.beginning_of_day..Time.current.end_of_day) }
  
  # Payment type scopes
  scope :cash_payments, -> { where(payment_type: :cash) }
  scope :card_payments, -> { where(payment_type: :card) }
  scope :mobile_money_payments, -> { where(payment_type: :mobile_money) }
  scope :bank_transfer_payments, -> { where(payment_type: :bank_transfer) }
  
  # ========================
  # FIXED: ADDED ALL MISSING METHODS
  # ========================
  
  # Get agency name (fixes undefined method error)
  def agency_name
    agency&.name || "Unknown Agency"
  end
  
  # Get agency code (convenience method)
  def agency_code
    agency&.code || "N/A"
  end
  
  # Format agency for display
  def formatted_agency
    "#{agency_code} - #{agency_name}"
  end
  
  # Display payment type in human-readable format (fixes undefined method error)
  def display_payment_type
    case payment_type&.to_sym
    when :cash
      "Cash"
    when :card
      "Credit/Debit Card"
    when :mobile_money
      "Mobile Money"
    when :bank_transfer
      "Bank Transfer"
    when :credit
      "Credit"
    else
      payment_type.to_s.titleize
    end
  end
  
  # Display status in human-readable format (fixes undefined method error)
  def display_status
    case status&.to_sym
    when :pending
      "Pending"
    when :completed
      "Completed"
    when :voided
      "Voided"
    when :refunded
      "Refunded"
    else
      status.to_s.titleize
    end
  end
  
  # Generate a checksum for receipt validation (fixes undefined method error)
  def receipt_checksum
    # Create a checksum based on transaction data to validate receipt authenticity
    data_to_hash = "#{receipt_number}#{transaction_id}#{amount.to_s.gsub('.', '')}#{created_at.to_i}"
    
    # Simple checksum
    require 'digest' unless defined?(Digest)
    Digest::MD5.hexdigest(data_to_hash)[0..7].upcase
  rescue => e
    "ERR-#{id}"
  end
  
  # Format receipt for printing
  def formatted_receipt
    lines = []
    lines << "=" * 40
    lines << "#{agency_name}"
    lines << "Receipt: #{receipt_number}"
    lines << "Date: #{created_at.strftime('%Y-%m-%d %H:%M:%S')}"
    lines << "-" * 40
    
    if route_code.present?
      lines << "Route: #{route_code}"
    end
    
    if passenger_count.present? && unit_fare.present?
      lines << "Passengers: #{passenger_count} x TT$#{'%.2f' % unit_fare}"
    end
    
    lines << "Amount: TT$#{'%.2f' % amount}"
    lines << "Payment: #{display_payment_type}"
    lines << "Status: #{display_status}"
    
    if cashier_session.present?
      lines << "Cashier: #{cashier_session.user&.name || 'System'}"
    end
    
    lines << "-" * 40
    lines << "Transaction ID: #{transaction_id}"
    lines << "Checksum: #{receipt_checksum}"
    lines << "=" * 40
    
    lines.join("\n")
  end
  
  # QR code data for receipt
  def qr_code_data
    {
      transaction_id: transaction_id,
      receipt_number: receipt_number,
      amount: amount,
      date: created_at.iso8601,
      checksum: receipt_checksum
    }.to_json
  end
  
  # Get user name (for receipt display)
  def user_name
    user&.name || 'System'
  end
  
  # Get vehicle display name (for receipt display)
  def vehicle_display
    if vehicle.present?
      "#{vehicle.make} #{vehicle.model} (#{vehicle.license_plate})"
    else
      'N/A'
    end
  end
  
  # Formatted date for receipt
  def formatted_date
    created_at.strftime('%B %d, %Y %I:%M %p')
  end
  
  # Get cashier name
  def cashier_name
    cashier_session&.user&.name || user_name
  end
  
  # ========================
  # EXISTING METHODS
  # ========================
  
  # Prevent deletion
  def destroy
    raise "POS transactions cannot be deleted. Use void! or refund! instead to maintain audit trail."
  end
  
  # Generate unique transaction ID
  def generate_transaction_id
    return if transaction_id.present?
    
    prefix = agency&.code || 'POS'
    timestamp = Time.now.strftime('%Y%m%d%H%M%S')
    random = SecureRandom.hex(3).upcase
    
    self.transaction_id = "#{prefix}-#{timestamp}-#{random}"
  end
  
  # Generate PTSC receipt number
  def generate_receipt_number
    return if receipt_number.present?
    return unless agency
    
    date_str = Time.current.strftime('%Y%m%d')
    sequence = PosTransaction
      .by_agency(agency_id)
      .where('receipt_number LIKE ?', "#{agency.code}-#{date_str}-%")
      .count + 1
    
    # Format: PTSC-20260120-00001
    self.receipt_number = "#{agency.code}-#{date_str}-#{sequence.to_s.rjust(5, '0')}"
  end
  
  # Calculate amount based on fare and passenger count
  def calculate_amount
    return unless unit_fare.present? && passenger_count.present?
    self.amount = unit_fare * passenger_count
  end
  
  # Set agency from user if not already set
  def set_agency_from_user
    self.agency_id ||= user&.agency_id
  end
  
  # Complete transaction
  def complete!
    return false unless pending?
    
    transaction do
      self.status = :completed
      self.save!
      
      # Update cashier session totals
      if cashier_session
        cashier_session.update_from_transaction(self)
      end
      
      # Log completion
      log_audit_trail('completed', { amount: amount, payment_type: payment_type })
      
      true
    end
  rescue => e
    errors.add(:base, "Failed to complete transaction: #{e.message}")
    false
  end
  
  # Void transaction
  def void!(reason = nil)
    return false unless can_be_voided?
    
    transaction do
      update!(
        status: :voided,
        voided_at: Time.current,
        voided_by: User.current&.id || self.class.current_user&.id,
        notes: [notes, "VOIDED on #{Time.current.strftime('%Y-%m-%d %H:%M:%S')} by #{User.current&.name || self.class.current_user&.name}. Reason: #{reason || 'Not specified'}"].compact.join("\n\n")
      )
      
      # Update cashier session if exists
      if cashier_session
        cashier_session.update_for_void(self)
      end
      
      log_audit_trail('voided', { amount: amount, reason: reason })
    end
    true
  rescue => e
    errors.add(:base, "Failed to void transaction: #{e.message}")
    false
  end
  
  # Refund transaction
  def refund!(reason = nil)
    return false unless can_be_refunded?
    
    transaction do
      update!(
        status: :refunded,
        refunded_at: Time.current,
        refunded_by: User.current&.id || self.class.current_user&.id,
        notes: [notes, "REFUNDED on #{Time.current.strftime('%Y-%m-%d %H:%M:%S')} by #{User.current&.name || self.class.current_user&.name}. Reason: #{reason || 'Not specified'}"].compact.join("\n\n")
      )
      
      # Update cashier session if exists
      if cashier_session
        cashier_session.update_for_refund(self)
      end
      
      log_audit_trail('refunded', { amount: amount, reason: reason })
    end
    true
  rescue => e
    errors.add(:base, "Failed to refund transaction: #{e.message}")
    false
  end
  
  # Convert to invoice for accounting
  def convert_to_invoice
    return nil if invoice_id.present?
    
    Invoice.create(
      agency: agency,
      vehicle: vehicle,
      invoice_date: Date.today,
      due_date: Date.today + 30.days,
      invoice_number: "INV-POS-#{receipt_number}",
      vendor: "PTSC Passenger",
      amount: amount,
      status: 'pending',
      category: 'transport_fare',
      notes: "Converted from PTSC POS transaction #{receipt_number}",
      pos_transaction_id: id
    )
  end
  
  # Check if can be voided
  def can_be_voided?
    completed? && !voided? && !refunded? && created_at > 2.hours.ago
  end
  
  # Check if can be refunded
  def can_be_refunded?
    completed? && !voided? && !refunded?
  end
  
  # Check if receipt is valid
  def valid_receipt?
    return false unless receipt_number.present?
    
    # Basic format check: PTSC-YYYYMMDD-XXXXX
    parts = receipt_number.split('-')
    return false unless parts.length == 3
    
    agency_code, date_str, sequence = parts
    agency_code == agency.code && date_str.length == 8 && sequence.length == 5
  end
  
  # PTSC-specific helper methods
  
  def display_fare_class
    fare_class.present? ? fare_class.titleize : 'Adult'
  end
  
  def display_ticket_type
    ticket_type.present? ? ticket_type.titleize : 'Single'
  end
  
  def display_route
    route_code.present? ? route_code : 'N/A'
  end
  
  def journey_description
    if origin_stop.present? && destination_stop.present?
      "#{origin_stop} to #{destination_stop}"
    else
      'Point-to-Point'
    end
  end
  
  def formatted_amount
    "TT$#{'%.2f' % amount}"
  end
  
  def formatted_unit_fare
    unit_fare.present? ? "TT$#{'%.2f' % unit_fare}" : 'N/A'
  end
  
  # Get fare rule for this transaction
  def fare_rule
    return nil unless agency && route_code && fare_class
    @fare_rule ||= FareRule.find_by(agency: agency, route_code: route_code, fare_class: fare_class)
  end
  
  # Get route info
  def route_info
    return nil unless agency && route_code
    @route_info ||= Route.find_by(agency: agency, route_code: route_code)
  end
  
  # For dashboard statistics
  
  def self.daily_summary(agency_id, date = Date.today)
    transactions = by_agency(agency_id)
                   .where(created_at: date.beginning_of_day..date.end_of_day)
                   .completed
    
    {
      total_sales: transactions.sum(:amount),
      transaction_count: transactions.count,
      passenger_count: transactions.sum(:passenger_count),
      cash_sales: transactions.cash_payments.sum(:amount),
      card_sales: transactions.card_payments.sum(:amount),
      mobile_sales: transactions.mobile_money_payments.sum(:amount),
      bank_transfer_sales: transactions.bank_transfer_payments.sum(:amount)
    }
  end
  
  def self.route_analytics(agency_id, start_date = 30.days.ago, end_date = Time.current)
    by_agency(agency_id)
      .where(created_at: start_date..end_date)
      .completed
      .group(:route_code)
      .select(
        'route_code',
        'COUNT(*) as transaction_count',
        'SUM(amount) as total_sales',
        'SUM(passenger_count) as passenger_count'
      )
      .order('total_sales DESC')
  end
  
  # Class method to set current user for callbacks
  cattr_accessor :current_user
  
  class << self
    def with_current_user(user)
      self.current_user = user
      yield
    ensure
      self.current_user = nil
    end
  end
  
  private
  
  def update_cashier_session_totals
    return unless cashier_session_id_before_last_save && cashier_session_id_before_last_save != cashier_session_id
    
    # Remove from old session
    old_session = CashierSession.find_by(id: cashier_session_id_before_last_save)
    if old_session && completed?
      old_session.update_for_void(self)
    end
    
    # Add to new session
    if cashier_session && completed?
      cashier_session.update_from_transaction(self)
    end
  end
  
  def log_status_change
    return unless saved_change_to_status?
    
    old_status, new_status = saved_change_to_status
    log_audit_trail('status_change', { 
      from: old_status, 
      to: new_status,
      changed_at: Time.current
    })
  end
  
  def log_audit_trail(action, details = {})
    user = User.current || self.class.current_user
    return unless user && defined?(AuditLog)
    
    AuditLog.create(
      user: user,
      action: action,
      resource: self,
      details: {
        transaction_id: transaction_id,
        receipt_number: receipt_number,
        amount: amount,
        route_code: route_code
      }.merge(details)
    )
  end
end