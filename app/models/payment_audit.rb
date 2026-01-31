# app/models/payment_audit.rb
class PaymentAudit < ApplicationRecord
  belongs_to :purchase_order
  belongs_to :user, optional: true

  # Rails 8-safe enum syntax (string-backed)
  enum :action, {
    initiated:  "initiated",
    authorized: "authorized",
    processed:  "processed",
    completed:  "completed",
    failed:     "failed",
    retried:    "retried",
    refunded:   "refunded",
    disputed:   "disputed"
  }, prefix: true

  # Store metadata as JSON (works with json/jsonb or text columns)
  # If your column is already json/jsonb, this is fine.
  attribute :metadata, :json, default: {}

  validates :action, presence: true
  validates :purchase_order_id, presence: true

  before_validation :ensure_metadata_hash
  before_create :capture_request_info

  scope :recent, -> { order(created_at: :desc) }
  scope :for_purchase_order, ->(po_id) { where(purchase_order_id: po_id) }
  scope :by_action, ->(action) { where(action: action) }
  scope :in_date_range, ->(start_date, end_date) do
    where(created_at: start_date.beginning_of_day..end_date.end_of_day)
  end

  def self.log(purchase_order, user, action, metadata = {})
    user ||= purchase_order.try(:payment_processed_by) || User.first
    create!(
      purchase_order: purchase_order,
      user: user,
      action: action,
      metadata: (metadata || {}).merge(timestamp: Time.current.iso8601),
      ip_address: Thread.current[:request]&.remote_ip,
      user_agent: Thread.current[:request]&.user_agent
    )
  end


  def self.create_audit_trail(purchase_order)
    return unless purchase_order&.payment_initiated_at

    log(
      purchase_order,
      purchase_order.respond_to?(:payment_processed_by) ? purchase_order.payment_processed_by : nil,
      :initiated,
      {
        amount: purchase_order.amount,
        payment_method: purchase_order.payment_method,
        card_last_four: purchase_order.try(:last_four_digits),
        reference: purchase_order.payment_reference
      }.compact
    )
  end

  def action_humanized
    action.to_s.humanize.titleize
  end

  def action_badge_color
    case action
    when "initiated", "retried" then "primary"
    when "authorized"          then "info"
    when "processed"           then "warning"
    when "completed"           then "success"
    when "failed", "disputed"  then "danger"
    when "refunded"            then "secondary"
    else "light"
    end
  end

  def formatted_metadata
    return "" if metadata.blank?

    metadata
      .reject { |k, _| k.to_s == "timestamp" }
      .map { |k, v| "#{k.to_s.humanize.titleize}: #{format_value(v)}" }
      .join("\n")
  end

  def duration_from_previous
    return nil unless purchase_order

    prev = purchase_order.payment_audits
      .where("created_at < ?", created_at)
      .order(created_at: :desc)
      .first

    return nil unless prev
    (created_at - prev.created_at).to_i
  end

  private

  def ensure_metadata_hash
    self.metadata = {} if metadata.nil?
    self.metadata = JSON.parse(metadata) if metadata.is_a?(String)
  rescue JSON::ParserError
    self.metadata = {}
  end

  def capture_request_info
    req = Thread.current[:request]
    self.ip_address ||= req&.remote_ip || "127.0.0.1"
    self.user_agent ||= req&.user_agent || "rails_runner"
  end

  def format_value(value)
    case value
    when Hash, Array
      JSON.pretty_generate(value)
    when Time, DateTime, ActiveSupport::TimeWithZone
      value.strftime("%b %d, %Y %I:%M %p")
    when BigDecimal
      format("TTD %.2f", value.to_f)
    else
      value.to_s
    end
  end
end
