# app/models/cashier_session.rb
class CashierSession < ApplicationRecord
  belongs_to :user
  belongs_to :agency
  belongs_to :closed_by, class_name: 'User', optional: true
  has_many :pos_transactions
  
  enum :status, { open: 0, closed: 1, suspended: 2 }
  
  validates :starting_cash, numericality: { greater_than_or_equal_to: 0 }
  validates :ending_cash, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  
  # Callbacks
  before_create :calculate_defaults
  before_save :update_totals_if_needed
  after_save :log_status_change, if: :saved_change_to_status?
  
  # Scopes
  scope :open, -> { where(status: :open) }
  scope :closed, -> { where(status: :closed) }
  scope :today, -> { where(opened_at: Time.current.beginning_of_day..Time.current.end_of_day) }
  scope :by_user, ->(user_id) { where(user_id: user_id) }
  scope :by_agency, ->(agency_id) { where(agency_id: agency_id) }
  scope :recent, -> { order(opened_at: :desc) }
  
  # Create new cashier session
  def self.open(user:, agency:, starting_cash: 0.0)
    # Close any existing open sessions for this user
    where(user: user, agency: agency, status: :open)
      .update_all(status: :closed, closed_at: Time.current, closed_by_id: user.id)
    
    session = create(
      user: user,
      agency: agency,
      status: :open,
      opened_at: Time.current,
      starting_cash: starting_cash,
      total_sales: 0.0,
      transaction_count: 0,
      voided_total: 0.0,
      voided_count: 0,
      refunded_total: 0.0,
      refunded_count: 0,
      cash_total: 0.0,
      card_total: 0.0,
      mobile_money_total: 0.0,
      bank_transfer_total: 0.0
    )
    
    # FIXED: Call create_audit_log on user instead of log_audit_trail
    if session.persisted? && user.respond_to?(:create_audit_log)
      user.create_audit_log(:opened, session, { starting_cash: starting_cash })
    end
    
    session
  end
  
  # Close cashier session
  def close(ending_cash:, counted_by:)
    return false unless can_close?
    
    transaction do
      calculate_totals
      
      self.status = :closed
      self.closed_at = Time.current
      self.ending_cash = ending_cash
      self.closed_by = counted_by
      self.discrepancy = calculated_discrepancy
      
      save!
      
      # FIXED: Call create_audit_log on counted_by user
      if counted_by.respond_to?(:create_audit_log)
        counted_by.create_audit_log(:closed, self, { 
          ending_cash: ending_cash, 
          discrepancy: discrepancy,
          counted_by: counted_by.email 
        })
      end
      
      true
    end
  rescue => e
    errors.add(:base, "Failed to close session: #{e.message}")
    false
  end
  
  # Reopen a closed session (for corrections)
  def reopen(reason: nil)
    return false unless closed?
    
    transaction do
      self.status = :open
      self.closed_at = nil
      self.closed_by_id = nil
      self.discrepancy = nil
      self.notes = [notes, "REOPENED on #{Time.current.strftime('%Y-%m-%d %H:%M:%S')} by #{Current.user&.name || User.current&.name}. Reason: #{reason || 'Not specified'}"].compact.join("\n\n")
      
      save!
      
      # FIXED: Call create_audit_log on current user
      user = Current.user || User.current
      if user&.respond_to?(:create_audit_log)
        user.create_audit_log(:reopened, self, { reason: reason })
      end
      
      true
    end
  rescue => e
    errors.add(:base, "Failed to reopen session: #{e.message}")
    false
  end
  
  # Calculate all totals
  def calculate_totals
    self.total_sales = pos_transactions.completed.sum(:amount)
    self.transaction_count = pos_transactions.completed.count
    self.voided_total = pos_transactions.voided.sum(:amount)
    self.voided_count = pos_transactions.voided.count
    self.refunded_total = pos_transactions.refunded.sum(:amount)
    self.refunded_count = pos_transactions.refunded.count
    
    # Payment method totals
    self.cash_total = pos_transactions.completed.cash_payments.sum(:amount)
    self.card_total = pos_transactions.completed.card_payments.sum(:amount)
    self.mobile_money_total = pos_transactions.completed.mobile_money_payments.sum(:amount)
    self.bank_transfer_total = pos_transactions.completed.bank_transfer_payments.sum(:amount)
    
    save if changed?
  end
  
  # Calculate discrepancy
  def calculated_discrepancy
    return nil unless ending_cash && closed?
    ending_cash - (starting_cash + cash_total - refunded_total)
  end
  
  # Duration in seconds
  def duration
    return nil unless opened_at
    end_time = closed_at || Time.current
    (end_time - opened_at).to_i
  end
  
  # Net sales (after voids and refunds)
  def net_sales
    total_sales - voided_total - refunded_total
  end
  
  # Expected cash in drawer
  def cash_expected
    starting_cash + cash_total - refunded_total
  end
  
  # Check if can be closed
  def can_close?
    open? && transaction_count > 0
  end
  
  # Update totals from transaction
  def update_from_transaction(transaction)
    return unless transaction.completed?
    
    increment!(:transaction_count)
    increment!(:total_sales, transaction.amount)
    
    case transaction.payment_type.to_sym
    when :cash
      increment!(:cash_total, transaction.amount)
    when :card
      increment!(:card_total, transaction.amount)
    when :mobile_money
      increment!(:mobile_money_total, transaction.amount)
    when :bank_transfer
      increment!(:bank_transfer_total, transaction.amount)
    end
    
    # FIXED: Use transaction's user for audit log
    user = transaction.user || User.current
    if user&.respond_to?(:create_audit_log)
      user.create_audit_log(:transaction_added, self, { 
        transaction_id: transaction.id,
        amount: transaction.amount,
        payment_type: transaction.payment_type 
      })
    end
  end
  
  # Update for void
  def update_for_void(transaction)
    return unless transaction.voided?
    
    increment!(:voided_count)
    increment!(:voided_total, transaction.amount)
    decrement!(:total_sales, transaction.amount)
    
    case transaction.payment_type.to_sym
    when :cash
      decrement!(:cash_total, transaction.amount)
    when :card
      decrement!(:card_total, transaction.amount)
    when :mobile_money
      decrement!(:mobile_money_total, transaction.amount)
    when :bank_transfer
      decrement!(:bank_transfer_total, transaction.amount)
    end
    
    # FIXED: Use transaction's user for audit log
    user = transaction.user || User.current
    if user&.respond_to?(:create_audit_log)
      user.create_audit_log(:transaction_voided, self, { 
        transaction_id: transaction.id,
        amount: transaction.amount 
      })
    end
  end
  
  # Update for refund
  def update_for_refund(transaction)
    return unless transaction.refunded?
    
    increment!(:refunded_count)
    increment!(:refunded_total, transaction.amount)
    decrement!(:total_sales, transaction.amount)
    
    case transaction.payment_type.to_sym
    when :cash
      decrement!(:cash_total, transaction.amount)
    when :card
      decrement!(:card_total, transaction.amount)
    when :mobile_money
      decrement!(:mobile_money_total, transaction.amount)
    when :bank_transfer
      decrement!(:bank_transfer_total, transaction.amount)
    end
    
    # FIXED: Use transaction's user for audit log
    user = transaction.user || User.current
    if user&.respond_to?(:create_audit_log)
      user.create_audit_log(:transaction_refunded, self, { 
        transaction_id: transaction.id,
        amount: transaction.amount 
      })
    end
  end
  
  # Formatting helpers
  def formatted_starting_cash
    "TT$#{'%.2f' % starting_cash}"
  end
  
  def formatted_ending_cash
    ending_cash ? "TT$#{'%.2f' % ending_cash}" : "Not closed"
  end
  
  def formatted_total_sales
    "TT$#{'%.2f' % total_sales}"
  end
  
  def formatted_net_sales
    "TT$#{'%.2f' % net_sales}"
  end
  
  def formatted_discrepancy
    return "N/A" unless discrepancy
    "TT$#{'%.2f' % discrepancy.abs}"
  end
  
  def discrepancy_status
    return "pending" unless discrepancy
    discrepancy.zero? ? "balanced" : discrepancy > 0 ? "overage" : "shortage"
  end
  
  def formatted_duration
    return "Active" unless closed_at && opened_at
    seconds = duration
    hours = seconds / 3600
    minutes = (seconds % 3600) / 60
    seconds = seconds % 60
    "#{hours}h #{minutes}m #{seconds}s"
  end
  
  # Payment method breakdown
  def payment_breakdown
    {
      cash: cash_total,
      card: card_total,
      mobile_money: mobile_money_total,
      bank_transfer: bank_transfer_total
    }
  end
  
  # Summary for display
  def summary
    {
      id: id,
      opened_at: opened_at,
      closed_at: closed_at,
      duration: formatted_duration,
      user_name: user&.display_name,
      transactions: transaction_count,
      total_sales: formatted_total_sales,
      net_sales: formatted_net_sales,
      cash_expected: "TT$#{'%.2f' % cash_expected}",
      discrepancy: formatted_discrepancy,
      status: discrepancy_status,
      payment_breakdown: payment_breakdown
    }
  end
  
  # Export to CSV
  def to_csv
    CSV.generate(headers: true) do |csv|
      csv << ['Date', 'Time', 'Receipt #', 'Route', 'Fare Class', 'Passengers', 'Amount', 'Payment Method', 'Status']
      
      pos_transactions.order(:created_at).each do |t|
        csv << [
          t.created_at.to_date,
          t.created_at.strftime('%H:%M:%S'),
          t.receipt_number,
          t.route_code,
          t.fare_class,
          t.passenger_count,
          t.amount,
          t.payment_type,
          t.status
        ]
      end
    end
  end
  
  private
  
  def calculate_defaults
    self.total_sales ||= 0.0
    self.transaction_count ||= 0
    self.voided_total ||= 0.0
    self.voided_count ||= 0
    self.refunded_total ||= 0.0
    self.refunded_count ||= 0
    self.cash_total ||= 0.0
    self.card_total ||= 0.0
    self.mobile_money_total ||= 0.0
    self.bank_transfer_total ||= 0.0
  end
  
  def update_totals_if_needed
    return unless closed? && ending_cash_changed?
    self.discrepancy = calculated_discrepancy
  end
  
  def log_status_change
    return unless saved_change_to_status?
    
    old_status, new_status = saved_change_to_status
    user = Current.user || User.current
    if user&.respond_to?(:create_audit_log)
      user.create_audit_log(:status_change, self, { 
        from: old_status, 
        to: new_status,
        changed_at: Time.current
      })
    end
  end
  
  # REMOVED: The problematic log_audit_trail method that was causing the error
  # def log_audit_trail(resource, action, details = {})
  #   user = User.current || Current.user
  #   return unless user && defined?(AuditLog)
  #   
  #   AuditLog.create(
  #     user: user,
  #     action: action.to_s,
  #     resource: resource,
  #     details: details,
  #     ip_address: Current.ip_address,
  #     user_agent: Current.user_agent
  #   )
  # end
end