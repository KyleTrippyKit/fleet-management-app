# frozen_string_literal: true

# app/models/quotation.rb
# UPDATED: Added polymorphic client association for Agency/Client
# UPDATED: Improved client type handling

class Quotation < ApplicationRecord
  # ------------------------------------------------------------
  # Safety: clear any problematic alias that can break associations
  # ------------------------------------------------------------
  # Commenting this out as recommended unless we know why it's needed
  # self.attribute_aliases = attribute_aliases.except("quotation_line_items")

  # ------------------------------------------------------------
  # Associations
  # ------------------------------------------------------------
  belongs_to :vehicle, optional: true
  belongs_to :rfq, optional: true
  belongs_to :work_order, optional: true
  
  include Auditable
  
  # Keep agency for backward compatibility
  belongs_to :agency, optional: true
  
  # NEW: Polymorphic client association (can be Agency or Client)
  belongs_to :client, polymorphic: true, optional: true

  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :submitted_by, class_name: "User", optional: true

  # purchase_orders has quotation_id (schema confirms)
  has_one :purchase_order, dependent: :nullify

  has_many :quotation_line_items, dependent: :destroy

  # ✅ Backward-compatible association name (so forms using :line_items still save)
  has_many :line_items,
          class_name: "QuotationLineItem",
          foreign_key: :quotation_id,
          inverse_of: :quotation,
          dependent: :destroy

  accepts_nested_attributes_for :quotation_line_items,
    allow_destroy: true,
    reject_if: proc { |attributes| attributes["description"].blank? }

  # ✅ If your form submits line_items_attributes, this will now work too
  accepts_nested_attributes_for :line_items,
    allow_destroy: true,
    reject_if: proc { |attributes| attributes["description"].blank? }

  has_many :quotation_jobs, dependent: :destroy
  accepts_nested_attributes_for :quotation_jobs, 
    allow_destroy: true,
    reject_if: proc { |attributes| attributes['name'].blank? }

  has_many :quotation_job_parts, through: :quotation_jobs

  # ------------------------------------------------------------
  # Enums
  # ------------------------------------------------------------
  enum :status, {
    draft: 0,
    sent: 1,
    accepted: 2,
    rejected: 3,
    expired: 4,
    converted: 5,
    pending_acceptance: 6,
    partially_rejected: 7,
    superseded: 8
  }, default: :draft

  # ------------------------------------------------------------
  # Validations
  # ------------------------------------------------------------
  validates :quote_number, presence: true, uniqueness: true
  validates :vendor, presence: true
  validates :valid_from, :valid_to, presence: true
  validates :amount, numericality: { greater_than_or_equal_to: 0 }
  # ✅ Only require amount > 0 for non-draft statuses
  validates :amount, numericality: { greater_than: 0 }, if: :requires_positive_amount?

  validate :valid_date_range
  validate :ensure_prices_present_before_conversion, if: :converting_to_converted?

  # ------------------------------------------------------------
  # Scopes
  # ------------------------------------------------------------
  scope :pending, -> { where(status: [:draft, :sent, :pending_acceptance]) }
  scope :active, -> { where("valid_to >= ?", Date.current).where(status: [:draft, :sent, :pending_acceptance]) }
  scope :this_month, -> { where(created_at: Time.current.beginning_of_month..Time.current.end_of_month) }
  scope :expiring_soon, ->(days = 7) { where(valid_to: Date.current..(Date.current + days.days)).where(status: [:draft, :sent, :pending_acceptance]) }
  scope :expired, -> { where("valid_to < ?", Date.current).or(where(status: :expired)) }
  scope :accepted, -> { where(status: :accepted) }
  scope :rejected, -> { where(status: :rejected) }
  scope :converted, -> { where(status: :converted) }
  scope :pending_acceptance, -> { where(status: :pending_acceptance) }
  scope :by_vendor, ->(vendor) { vendor.present? ? where("vendor ILIKE ?", "%#{vendor}%") : all }
  scope :search, ->(term) { return all unless term.present?; where("quote_number ILIKE :t OR vendor ILIKE :t OR notes ILIKE :t", t: "%#{term}%") }
  scope :for_agency, ->(agency) { return all unless agency.present?; left_joins(:vehicle).where("quotations.agency_id = :aid OR vehicles.agency_id = :aid", aid: agency.id) }
  # NEW: Scope for client type
  scope :for_client, ->(client) { where(client: client) if client.present? }
  scope :agency_quotations, -> { where(client_type: 'Agency') }
  scope :client_quotations, -> { where(client_type: ['corporate', 'individual']) }

  # ------------------------------------------------------------
  # Callbacks
  # ------------------------------------------------------------
  before_validation :generate_quote_number, on: :create
  before_validation :set_default_dates, on: :create
  before_validation :set_agency_from_vehicle, if: -> { agency_id.blank? && vehicle_id.present? }
  before_validation :set_client_from_vehicle, if: -> { client_id.blank? && vehicle_id.present? }
  # ✅ Agency fallback for create
  before_validation :set_agency_fallback, on: :create
  before_validation :recalculate_amount_from_children
  before_save :update_status_timestamps, if: :will_save_change_to_status?

  # ------------------------------------------------------------
  # Client Helper Methods
  # ------------------------------------------------------------
  
  # Get the client name regardless of type
  def client_name
    if client.is_a?(Agency)
      client.name
    elsif client.is_a?(Client)
      client.name
    elsif agency.present?
      agency.name
    else
      "Unknown"
    end
  end
  
  # Get display info about the client type
  def client_type_display
    if client.is_a?(Agency)
      "Agency: #{client.code}"
    elsif client.is_a?(Client)
      "Client: #{client.client_type.humanize}"
    elsif agency.present?
      "Agency: #{agency.code}"
    else
      "Unknown"
    end
  end
  
  # Check if client is an agency
  def for_agency?
    client.is_a?(Agency) || agency.present?
  end
  
  # Check if client is a client
  def for_client?
    client.is_a?(Client)
  end

  # ------------------------------------------------------------
  # User-friendly Status Methods
  # ------------------------------------------------------------
  
  # Friendly status name for VMCOTT workspace view
  def vmcott_friendly_status
    case status.to_sym
    when :draft
      '⚪ Draft - VMCOTT Processing'
    when :sent
      '🔵 Sent to Client'
    when :pending_acceptance
      '🟡 Under Client Review'
    when :accepted
      '🟢 Accepted by Client'
    when :rejected
      '🔴 Rejected by Client'
    when :expired
      '⚫ Expired'
    when :converted
      '🔵 Converted to PO'
    when :partially_rejected
      '🟠 Partially Rejected'
    else
      status.humanize
    end
  end

  # Friendly status name for Client/Finance view
  def client_friendly_status
    case status.to_sym
    when :draft
      '⚪ Draft'
    when :sent
      '🔵 Under Review'
    when :pending_acceptance
      '🟡 Awaiting Your Decision'
    when :accepted
      '🟢 Accepted - Ready for PO'
    when :rejected
      '🔴 Rejected'
    when :expired
      '⚫ Expired'
    when :converted
      '🔵 Converted to PO'
    when :partially_rejected
      '🟠 Partially Rejected'
    else
      status.humanize
    end
  end

  # Priority level for finance team
  def finance_priority
    return nil unless status.to_sym == :sent
    
    if created_at < 3.days.ago
      { level: 'high', text: '🔴 High Priority - Pending over 3 days', badge: 'danger' }
    elsif created_at < 7.days.ago
      { level: 'medium', text: '🟡 Medium Priority - Pending over 1 week', badge: 'warning' }
    else
      { level: 'normal', text: '🔵 Normal Priority', badge: 'info' }
    end
  end

  # Expiry warning
  def expiry_warning
    return nil unless valid_to.present? && status.to_sym == :sent
    
    days_left = (valid_to.to_date - Date.current).to_i
    return nil if days_left <= 0
    
    if days_left <= 3
      { level: 'critical', text: "⚠️ Expires in #{days_left} days", badge: 'danger' }
    elsif days_left <= 7
      { level: 'warning', text: "⚠️ Expires in #{days_left} days", badge: 'warning' }
    else
      nil
    end
  end

  # Status badge color for Bootstrap
  def status_badge_color(context = 'workspace')
    case status.to_sym
    when :draft then 'secondary'
    when :sent then context == 'workspace' ? 'primary' : 'info'
    when :pending_acceptance then 'warning'
    when :accepted then 'success'
    when :rejected then 'danger'
    when :expired then 'dark'
    when :converted then 'info'
    when :partially_rejected then 'danger'
    else 'light'
    end
  end

  # ------------------------------------------------------------
  # Status / time helpers
  # ------------------------------------------------------------
  def expired?
    valid_to.present? && valid_to < Date.current
  end

  def expiring_soon?(days = 7)
    return false if valid_to.blank?
    return false if expired?
    valid_to <= (Date.current + days.days)
  end

  # ------------------------------------------------------------
  # Locking / permissions
  # ------------------------------------------------------------
  def locked?
    sent? || accepted? || rejected? || converted?
  end

  def can_be_duplicated?
    persisted?
  end

  def can_be_edited?
    persisted? && !locked?
  end

  def can_be_deleted?
    persisted? && draft?
  end

  def can_be_sent?
    draft? && !expired?
  end

  def can_be_accepted?
    [:draft, :sent, :pending_acceptance].include?(status.to_sym) && !expired?
  end

  def can_be_rejected?
    [:draft, :sent, :accepted, :pending_acceptance].include?(status.to_sym) && !expired?
  end

  def can_be_converted_to_po?
    [:accepted, :pending_acceptance].include?(status.to_sym)
  end

  # ------------------------------------------------------------
  # Amount calculations
  # ------------------------------------------------------------
  def recalculate_amount!
    recalculate_amount_from_children
    save!
  end

  # Backward compatibility
  def calculate_total_amount
    recalculate_amount!
  end

  # Explicit calculation methods
  def line_items_total
    quotation_line_items.sum do |li|
      qty  = li.quantity.to_i
      unit = li.unit_price.to_f
      (qty * unit)
    end
  end

  def labor_total
    quotation_jobs.sum { |j| j.total_labor_cost.to_f }
  end

  def parts_total
    quotation_job_parts.sum do |p|
      if p.total_price.present?
        p.total_price.to_f
      else
        p.quantity.to_i * p.unit_price.to_f
      end
    end
  end

  def total_job_cost
    labor_total + parts_total
  end

  # ------------------------------------------------------------
  # State transitions
  # ------------------------------------------------------------
  def accept!
    update(status: :accepted, accepted_at: Time.current)
  end

  def reject!(reason = nil)
    rejection_note = "Rejected on #{Date.current}"
    rejection_note += ": #{reason}" if reason.present?

    update(
      status: :rejected,
      rejected_at: Time.current,
      notes: [notes, rejection_note].compact.join("\n\n")
    )
  end

  def expire!
    return unless valid_to.present?
    return unless valid_to < Date.current
    return unless [:draft, :sent, :pending_acceptance].include?(status.to_sym)
    update(status: :expired)
  end

  def send_to_client!
    return false if locked?
    update(status: :sent, sent_at: Time.current)
  end

  def submit_to_agency!
    return unless vendor == "VMCOTT"
    send_to_client!
  end

  def convert_to_purchase_order!
    return unless can_be_converted_to_po?
    update!(status: :converted, converted_at: Time.current)
  end

  # ------------------------------------------------------------
  # Display helpers
  # ------------------------------------------------------------
  def days_until_expiry
    return nil unless valid_to
    (valid_to - Date.current).to_i
  end

  def display_status
    case status.to_sym
    when :draft then "Draft"
    when :sent then "Sent to Client"
    when :accepted then "Accepted"
    when :rejected then "Rejected"
    when :expired then "Expired"
    when :converted then "Converted to PO"
    when :pending_acceptance then "Pending Acceptance"
    when :partially_rejected then "Partially Rejected"
    else status.to_s.humanize
    end
  end

  def status_color
    case status.to_sym
    when :draft then "secondary"
    when :sent then expired? ? "warning" : "info"
    when :accepted then "success"
    when :rejected then "danger"
    when :expired then "warning"
    when :converted then "primary"
    when :pending_acceptance then "warning"
    when :partially_rejected then "danger"
    else "dark"
    end
  end

  def status_icon
    case status.to_sym
    when :draft then "clock"
    when :sent then expired? ? "clock-history" : "send"
    when :accepted then "check-circle"
    when :rejected then "x-circle"
    when :expired then "clock-history"
    when :converted then "arrow-right-circle"
    when :pending_acceptance then "clock"
    when :partially_rejected then "x-circle"
    else "info-circle"
    end
  end

  def status_badge_class
    "badge bg-#{status_color}"
  end

  def formatted_amount
    ActionController::Base.helpers.number_to_currency(amount.to_f, unit: "$")
  end

  def formatted_amount_with_vat
    ActionController::Base.helpers.number_to_currency(total_with_vat, unit: "$")
  end

  def vat_amount
    amount.to_f * 0.125
  end

  def total_with_vat
    amount.to_f + vat_amount
  end

  def days_valid
    return 0 unless valid_from && valid_to
    (valid_to - valid_from).to_i
  end

  def urgency_level
    days_left = days_until_expiry.to_i
    if days_left <= 0
      "expired"
    elsif days_left <= 3
      "high"
    elsif days_left <= 7
      "medium"
    else
      "low"
    end
  end

  def urgency_badge_class
    case urgency_level
    when "expired" then "badge bg-danger"
    when "high" then "badge bg-warning text-dark"
    when "medium" then "badge bg-info"
    when "low" then "badge bg-success"
    else "badge bg-secondary"
    end
  end

  def client_name_display
    client_name
  end

  def client_code_display
    if client.is_a?(Agency)
      client.code
    elsif client.is_a?(Client)
      client.client_type
    elsif agency.present?
      agency.code
    else
      "N/A"
    end
  end

  # Aliases for backward compatibility
  def total_labor_cost
    labor_total
  end

  def total_parts_cost
    parts_total
  end

  def has_jobs?
    quotation_jobs.any?
  end

  def timeline_events
    events = []
    events << { event: "Quotation Created", date: created_at, user: created_by, description: "Quotation #{quote_number} created", icon: "file-earmark-plus", active: true }

    if sent? || accepted? || rejected? || converted?
      events << { event: "Sent to Client", date: sent_at || updated_at, description: "Quotation sent to client", icon: "send", active: sent_at.present? }
    end

    if accepted? && accepted_at
      events << { event: "Accepted", date: accepted_at, description: "Quotation accepted by client", icon: "check-circle", active: true }
    end

    if rejected? && rejected_at
      events << { event: "Rejected", date: rejected_at, description: "Quotation rejected", icon: "x-circle", active: true }
    end

    if converted? && converted_at
      events << { event: "Converted to PO", date: converted_at, description: "Converted to purchase order", icon: "cart-check", active: true }
    end

    if expired? && valid_to
      events << { event: "Expired", date: valid_to, description: "Quotation validity expired", icon: "clock-history", active: true }
    end

    events.sort_by { |e| e[:date] || Time.at(0) }
  end

  # Helper for conversion validation
  def converting_to_converted?
    will_save_change_to_status? && status.to_sym == :converted
  end

  # Helper for positive amount requirement
  def requires_positive_amount?
    !draft?
  end

  private

  def valid_date_range
    return unless valid_from && valid_to
    errors.add(:valid_to, "must be after valid from date") if valid_to <= valid_from
  end

  def ensure_prices_present_before_conversion
    quotation_line_items.each do |item|
      if item.unit_price.blank? || item.unit_price.to_f <= 0
        errors.add(:base, "Line item '#{item.description}' must have a valid price")
        return
      end
    end

    quotation_job_parts.each do |part|
      if part.unit_price.blank? || part.unit_price.to_f <= 0
        errors.add(:base, "Part '#{part.part&.name || 'Unknown'}' must have a valid price")
        return
      end
    end
  end

  def set_agency_from_vehicle
    self.agency = vehicle.agency if vehicle&.agency
  end

  # NEW: Set client from vehicle's polymorphic owner
  def set_client_from_vehicle
    return unless vehicle&.owner.present?
    self.client = vehicle.owner
  end

  # Agency fallback for create
  def set_agency_fallback
    return if agency_id.present? || client_id.present?
    self.agency_id = created_by&.agency_id || Agency.find_by(code: "VMCOTT")&.id || Agency.first&.id
  end
  private :set_agency_fallback

  # Generate quote number that doesn't depend on vendor being present yet
  def generate_quote_number
    return if quote_number.present?
    date_part   = Time.current.strftime("%Y%m%d")
    random_part = SecureRandom.hex(4).upcase

    prefix = (vendor.to_s == "VMCOTT") ? "Q-VMC" : "Q"
    self.quote_number = "#{prefix}-#{date_part}-#{random_part}"
  end

  def set_default_dates
    self.valid_from ||= Date.current
    self.valid_to   ||= Date.current + 30.days
  end

  def update_status_timestamps
    case status.to_sym
    when :sent
      self.sent_at ||= Time.current
    when :accepted
      self.accepted_at ||= Time.current
    when :rejected
      self.rejected_at ||= Time.current
    when :converted
      self.converted_at ||= Time.current
    end
  end

  def recalculate_amount_from_children
    self.amount = (line_items_total + labor_total + parts_total).round(2)
    self.amount = 0.0 if amount.nil?  # Ensure never nil
  end
end