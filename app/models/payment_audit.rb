# app/models/payment_audit.rb
class PaymentAudit < ApplicationRecord
  belongs_to :purchase_order
  belongs_to :user, optional: true
  
  enum action: {
    initiated: 'initiated',
    authorized: 'authorized',
    processed: 'processed',
    completed: 'completed',
    failed: 'failed',
    retried: 'retried',
    refunded: 'refunded',
    disputed: 'disputed'
  }, _prefix: true
  
  serialize :metadata, JSON
  serialize :ip_address, type: String, accessor: :ip_address
  serialize :user_agent, type: String, accessor: :user_agent
  
  validates :action, presence: true
  validates :purchase_order_id, presence: true
  
  before_create :capture_request_info
  
  scope :recent, -> { order(created_at: :desc) }
  scope :for_purchase_order, ->(po_id) { where(purchase_order_id: po_id) }
  scope :by_action, ->(action) { where(action: action) }
  scope :in_date_range, ->(start_date, end_date) { 
    where(created_at: start_date.beginning_of_day..end_date.end_of_day) 
  }
  
  def self.log(purchase_order, user, action, metadata = {})
    create!(
      purchase_order: purchase_order,
      user: user,
      action: action,
      metadata: metadata.merge(
        timestamp: Time.current.iso8601
      )
    )
  end
  
  def self.create_audit_trail(purchase_order)
    # Create initial audit entry when payment is initiated
    return unless purchase_order.payment_initiated_at
    
    log(
      purchase_order,
      purchase_order.payment_processed_by,
      :initiated,
      {
        amount: purchase_order.amount,
        payment_method: purchase_order.payment_method,
        card_last_four: purchase_order.last_four_digits,
        reference: purchase_order.payment_reference
      }
    )
  end
  
  def action_humanized
    action.humanize.titleize
  end
  
  def action_badge_color
    case action
    when 'initiated', 'retried'
      'primary'
    when 'authorized'
      'info'
    when 'processed'
      'warning'
    when 'completed'
      'success'
    when 'failed', 'disputed'
      'danger'
    when 'refunded'
      'secondary'
    else
      'light'
    end
  end
  
  def formatted_metadata
    return '' if metadata.blank?
    
    formatted = []
    metadata.each do |key, value|
      next if key.to_s == 'timestamp'
      
      formatted_key = key.to_s.humanize.titleize
      formatted_value = format_value(value)
      formatted << "#{formatted_key}: #{formatted_value}"
    end
    
    formatted.join("\n")
  end
  
  def duration_from_previous
    return nil unless purchase_order
    
    previous_audit = purchase_order.payment_audits
      .where('created_at < ?', created_at)
      .order(created_at: :desc)
      .first
    
    return nil unless previous_audit
    
    (created_at - previous_audit.created_at).to_i
  end
  
  private
  
  def capture_request_info
    if Thread.current[:request]
      self.ip_address = Thread.current[:request].remote_ip
      self.user_agent = Thread.current[:request].user_agent
    end
  end
  
  def format_value(value)
    case value
    when Hash, Array
      JSON.pretty_generate(value)
    when Time, DateTime, ActiveSupport::TimeWithZone
      value.strftime('%b %d, %Y %I:%M %p')
    when BigDecimal
      'TTD ' + value.to_f.round(2).to_s
    else
      value.to_s
    end
  end
end