require 'csv'
class Quotation < ApplicationRecord
  # FIX: Clear any problematic attribute aliases
  self.attribute_aliases = attribute_aliases.except('quotation_line_items')
  # Associations
  belongs_to :vehicle, optional: true
  belongs_to :created_by, class_name: 'User'
  
  # Detailed line items
  has_many :quotation_line_items, dependent: :destroy
  alias_method :line_items, :quotation_line_items
  accepts_nested_attributes_for :quotation_line_items, allow_destroy: true
  
  # Enums
  enum :status, {
    draft: 0,
    sent: 1,
    accepted: 2,
    rejected: 3,
    expired: 4,
    converted: 5
  }, default: :draft
  
  # Validations
  validates :quote_number, presence: true, uniqueness: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :vendor, presence: true
  validates :valid_from, :valid_to, presence: true
  validate :valid_date_range
  
  # Scopes
  scope :pending, -> { where(status: [:draft, :sent]) }
  scope :active, -> { where('valid_to >= ?', Date.today).where(status: [:draft, :sent]) }
  scope :expired, -> { where('valid_to < ?', Date.today).or(where(status: :expired)) }
  scope :accepted, -> { where(status: :accepted) }
  scope :rejected, -> { where(status: :rejected) }
  scope :converted, -> { where(status: :converted) }
  scope :this_month, -> { where(created_at: Time.current.beginning_of_month..Time.current.end_of_month) }
  
  # Expiring soon (within 7 days)
  scope :expiring_soon, -> { 
    where('valid_to BETWEEN ? AND ?', Date.today, Date.today + 7.days)
    .where(status: [:draft, :sent])
  }
  
  # Agency scope
  scope :for_agency, ->(agency) {
    return all unless agency.present?
    joins(:vehicle).where(vehicles: { agency_id: agency.id })
  }
  
  # Vendor scope
  scope :by_vendor, ->(vendor) { 
    where('vendor ILIKE ?', "%#{vendor}%") if vendor.present?
  }
  
  # Search scope
  scope :search, ->(term) {
    return unless term.present?
    where('quote_number ILIKE :term OR vendor ILIKE :term OR notes ILIKE :term', term: "%#{term}%")
  }
  
  # Callbacks
  before_validation :generate_quote_number, on: :create
  before_validation :set_default_dates, on: :create
  before_save :update_amount_from_line_items, if: :line_items_changed?
  after_save :update_status_timestamps
  
  # Instance Methods
  
  def generate_quote_number
    return if quote_number.present?
    date_part = Time.now.strftime('%Y%m%d')
    random_part = SecureRandom.hex(4).upcase
    self.quote_number = "RFQ-#{date_part}-#{random_part}"
  end
  
  def set_default_dates
    self.valid_from ||= Date.today
    self.valid_to ||= Date.today + 30.days
  end
  
  def accept!
    update(status: :accepted, accepted_at: Time.current)
  end
  
  def reject!(reason = nil)
    rejection_note = "Rejected on #{Date.today}"
    rejection_note += ": #{reason}" if reason.present?
    
    update(
      status: :rejected,
      rejected_at: Time.current,
      notes: [notes, rejection_note].compact.join("\n\n")
    )
  end
  
  def expire!
    return unless valid_to < Date.today && [:draft, :sent].include?(status.to_sym)
    update(status: :expired)
  end
  
  def convert_to_purchase_order!
    update(status: :converted, converted_at: Time.current)
  end
  
  def send_to_vendor!
    return if sent? || accepted? || rejected?
    update(status: :sent)
  end
  
  def update_amount_from_line_items
    return if quotation_line_items.empty?
    self.amount = quotation_line_items.sum(&:total_price)
  end
  
  def line_items_changed?
    quotation_line_items.any?(&:changed?)
  end
  
  def update_status_timestamps
    # Clear timestamps when status changes from accepted/rejected/converted
    if status_changed?
      case status_was.to_sym
      when :accepted
        update_column(:accepted_at, nil) unless accepted?
      when :rejected
        update_column(:rejected_at, nil) unless rejected?
      when :converted
        update_column(:converted_at, nil) unless converted?
      end
      
      # Set timestamp for new status
      case status.to_sym
      when :accepted
        update_column(:accepted_at, Time.current) if accepted_at.nil?
      when :rejected
        update_column(:rejected_at, Time.current) if rejected_at.nil?
      when :converted
        update_column(:converted_at, Time.current) if converted_at.nil?
      end
    end
  end
  
  # View Helper Methods
  
  def days_until_expiry
    return nil unless valid_to
    (valid_to - Date.today).to_i
  end
  
  def expired?
    valid_to < Date.today || status.to_sym == :expired
  end
  
  def display_status
    case status.to_sym
    when :draft then 'Draft'
    when :sent then 'Sent to Vendor'
    when :accepted then 'Accepted'
    when :rejected then 'Rejected'
    when :expired then 'Expired'
    when :converted then 'Converted to PO'
    else status.humanize
    end
  end
  
  def status_color
    case status.to_sym
    when :draft then 'secondary'
    when :sent then expired? ? 'warning' : 'info'
    when :accepted then 'success'
    when :rejected then 'danger'
    when :expired then 'warning'
    when :converted then 'primary'
    else 'dark'
    end
  end
  
  def status_badge_class
    "badge bg-#{status_color}"
  end
  
  def formatted_amount
    ActionController::Base.helpers.number_to_currency(amount, unit: "$")
  end
  
  def formatted_amount_with_vat
    ActionController::Base.helpers.number_to_currency(total_with_vat, unit: "$")
  end
  
  def vat_amount
    amount * 0.125
  end
  
  def total_with_vat
    amount + vat_amount
  end
  
  def days_valid
    return 0 unless valid_from && valid_to
    (valid_to - valid_from).to_i
  end
  
  def urgency_level
    days_left = days_until_expiry.to_i
    if days_left <= 0
      'expired'
    elsif days_left <= 3
      'high'
    elsif days_left <= 7
      'medium'
    else
      'low'
    end
  end
  
  def urgency_badge_class
    case urgency_level
    when 'expired' then 'badge bg-danger'
    when 'high' then 'badge bg-warning text-dark'
    when 'medium' then 'badge bg-info'
    when 'low' then 'badge bg-success'
    else 'badge bg-secondary'
    end
  end
  
  def can_be_accepted?
    [:draft, :sent].include?(status.to_sym) && !expired?
  end
  
  def can_be_rejected?
    [:draft, :sent, :accepted].include?(status.to_sym) && !expired?
  end
  
  def can_be_converted_to_po?
    status.to_sym == :accepted
  end
  
  def can_be_sent?
    draft? && !expired?
  end
  
  def can_be_edited?
    draft?
  end
  
  def timeline_events
    events = []
    
    # Creation event
    events << {
      event: 'RFQ Created',
      date: created_at,
      user: created_by,
      description: "RFQ #{quote_number} created",
      icon: 'file-earmark-plus'
    }
    
    # Sent event
    if [:sent, :accepted, :rejected].include?(status.to_sym)
      events << {
        event: 'Sent to Vendor',
        date: updated_at,
        description: "RFQ sent to #{vendor}",
        icon: 'send'
      }
    end
    
    # Acceptance event
    if accepted? && accepted_at
      events << {
        event: 'Accepted',
        date: accepted_at,
        description: "Quotation accepted by vendor",
        icon: 'check-circle'
      }
    end
    
    # Rejection event
    if rejected? && rejected_at
      events << {
        event: 'Rejected',
        date: rejected_at,
        description: "Quotation rejected",
        icon: 'x-circle'
      }
    end
    
    # Conversion event
    if converted? && converted_at
      events << {
        event: 'Converted to PO',
        date: converted_at,
        description: "Converted to purchase order",
        icon: 'cart-check'
      }
    end
    
    # Expiry event
    if expired? && valid_to
      events << {
        event: 'Expired',
        date: valid_to,
        description: "Quotation validity expired",
        icon: 'clock-history'
      }
    end
    
    events.sort_by { |e| e[:date] || Time.at(0) }
  end
  
  def agency
    vehicle&.agency
  end
  
  def agency_code
    agency&.code || vehicle&.service_owner
  end
  
  def agency_name
    agency&.name || vehicle&.service_owner || 'Fleet Management'
  end
  
  # For PDF generation
  def to_pdf
    content = "=" * 60 + "\n"
    content += "REQUEST FOR QUOTATION\n"
    content += "=" * 60 + "\n\n"
    
    content += "RFQ Details:\n"
    content += "  RFQ #: #{quote_number}\n"
    content += "  Date: #{created_at.strftime('%d %B, %Y')}\n"
    content += "  Vendor: #{vendor}\n"
    content += "  Valid From: #{valid_from.strftime('%d %B, %Y')}\n"
    content += "  Valid To: #{valid_to.strftime('%d %B, %Y')}\n"
    content += "  Status: #{display_status}\n\n"
    
    content += "Vehicle Information:\n"
    if vehicle
      content += "  Registration: #{vehicle.license_plate}\n"
      content += "  Make/Model: #{vehicle.make} #{vehicle.model}\n"
      content += "  Year: #{vehicle.year_of_manufacture}\n"
      content += "  Agency: #{agency_name}\n\n"
    else
      content += "  No vehicle assigned\n\n"
    end
    
    if quotation_line_items.any?
      content += "Line Items:\n"
      content += "-" * 60 + "\n"
      quotation_line_items.each_with_index do |item, index|
        content += "#{index + 1}. #{item.description}\n"
        content += "   Qty: #{item.quantity} x $#{'%.2f' % item.unit_price} = $#{'%.2f' % item.total_price}\n"
        content += "   Specs: #{item.specifications}\n\n" if item.specifications.present?
      end
      content += "-" * 60 + "\n"
    end
    
    content += "Financial Information:\n"
    content += "  Quoted Amount: $#{'%.2f' % amount}\n"
    content += "  VAT (12.5%): $#{'%.2f' % vat_amount}\n"
    content += "  Total Amount: $#{'%.2f' % total_with_vat}\n\n"
    
    if notes.present?
      content += "Notes:\n#{notes}\n\n"
    end
    
    content += "=" * 60 + "\n"
    content += "Generated on: #{Time.current.strftime('%d %B, %Y at %H:%M')}\n"
    content += "=" * 60
    content
  end
  
  private
  
  def valid_date_range
    return unless valid_from && valid_to
    errors.add(:valid_to, "must be after valid from date") if valid_to <= valid_from
  end
end