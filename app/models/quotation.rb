class Quotation < ApplicationRecord
  # FIX: Clear any problematic attribute aliases
  self.attribute_aliases = attribute_aliases.except('quotation_line_items')
  
  # Associations
  belongs_to :vehicle, optional: true
  belongs_to :created_by, class_name: 'User'
  belongs_to :rfq, optional: true
  
  # ADDED: Direct agency association for receiving quotations
  belongs_to :agency
  
  # Detailed line items
  has_many :quotation_line_items, dependent: :destroy
  alias_method :line_items, :quotation_line_items
  accepts_nested_attributes_for :quotation_line_items, allow_destroy: true
  
  # Quotation Jobs
  has_many :quotation_jobs, dependent: :destroy
  accepts_nested_attributes_for :quotation_jobs, allow_destroy: true
  has_many :quotation_job_parts, through: :quotation_jobs
  
  # Purchase Order reference
  belongs_to :purchase_order, optional: true
  
  # Timestamps for different statuses
  attribute :sent_at, :datetime
  attribute :accepted_at, :datetime
  attribute :rejected_at, :datetime
  
  # Enums
  enum :status, {
    draft: 0,
    sent: 1,
    accepted: 2,
    rejected: 3,
    expired: 4,
    converted: 5,
    pending_acceptance: 6,
    partially_rejected: 7
  }, default: :draft
  
  # Validations
  validates :quote_number, presence: true, uniqueness: true
  validates :amount, presence: true, numericality: { greater_than: 0 }, unless: :draft?
  validates :vendor, presence: true
  validates :valid_from, :valid_to, presence: true
  validate :valid_date_range
  validate :ensure_prices_present_before_conversion
  
  # Scopes
  scope :pending, -> { where(status: [:draft, :sent, :pending_acceptance]) }
  scope :active, -> { where('valid_to >= ?', Date.today).where(status: [:draft, :sent, :pending_acceptance]) }
  scope :expired, -> { where('valid_to < ?', Date.today).or(where(status: :expired)) }
  scope :accepted, -> { where(status: :accepted) }
  scope :rejected, -> { where(status: :rejected) }
  scope :converted, -> { where(status: :converted) }
  scope :pending_acceptance, -> { where(status: :pending_acceptance) }
  scope :this_month, -> { where(created_at: Time.current.beginning_of_month..Time.current.end_of_month) }
  
  # Expiring soon (within 7 days)
  scope :expiring_soon, -> { 
    where('valid_to BETWEEN ? AND ?', Date.today, Date.today + 7.days)
    .where(status: [:draft, :sent, :pending_acceptance])
  }
  
  # Agency scope - UPDATED to include direct agency association
  scope :for_agency, ->(agency) {
    return all unless agency.present?
    where("agency_id = ? OR (vehicle_id IS NOT NULL AND vehicles.agency_id = ?)", agency.id, agency.id)
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
  before_save :update_amount_from_jobs, if: :jobs_changed?
  before_save :update_status_timestamps
  before_save :set_agency_from_vehicle, if: -> { agency_id.blank? && vehicle_id.present? }
  
  # Instance Methods
  
  # ADDED: Set agency from vehicle if not set
  def set_agency_from_vehicle
    self.agency = vehicle.agency if vehicle && vehicle.agency
  end
  
  # ADDED: Validate that prices are present before conversion to PO
  def ensure_prices_present_before_conversion
    return unless status_changed? && converted?
    
    # Check quotation line items
    quotation_line_items.each do |item|
      if item.unit_price.blank? || item.unit_price <= 0
        errors.add(:base, "Line item '#{item.description}' must have a valid price")
        return false
      end
    end
    
    # Check quotation job parts
    quotation_job_parts.each do |part|
      if part.unit_price.blank? || part.unit_price <= 0
        errors.add(:base, "Part '#{part.part&.name || 'Unknown'}' must have a valid price")
        return false
      end
    end
    
    true
  end
  
  def requesting_agency
    Agency.find_by(code: 'VMCOTT') || Agency.first
  end
  
  def calculate_total_amount
    total = 0
    quotation_jobs.each do |job|
      total += job.total_labor_cost || 0
      job.quotation_job_parts.each do |part|
        total += part.total_price || 0
      end
    end
    total
  end
  
  def generate_quote_number
    return if quote_number.present?
    date_part = Time.now.strftime('%Y%m%d')
    random_part = SecureRandom.hex(4).upcase
    
    # Check if VMCOTT quotation
    if vendor == 'VMCOTT'
      self.quote_number = "Q-VMC-#{date_part}-#{random_part}"
    else
      self.quote_number = "Q-#{date_part}-#{random_part}"
    end
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
    return unless can_be_converted_to_po?
    
    # Ensure all prices are valid before conversion
    unless ensure_prices_present_before_conversion
      raise ActiveRecord::RecordInvalid.new(self)
    end
    
    update(status: :converted, converted_at: Time.current)
  end
  
  def send_to_vendor!
    return if sent? || accepted? || rejected?
    update(status: :sent, sent_at: Time.current)
  end
  
  def submit_to_agency!
    return unless vendor == 'VMCOTT'
    send_to_vendor!
  end
  
  def update_amount_from_line_items
    return if quotation_line_items.empty?
    self.amount = quotation_line_items.sum(&:total_price)
  end
  
  def update_amount_from_jobs
    return if quotation_jobs.empty?
    
    labor_total = quotation_jobs.sum(&:total_labor_cost).to_f
    parts_total = quotation_job_parts.sum(&:total_price).to_f
    line_items_total = quotation_line_items.sum(&:total_price).to_f
    
    self.amount = line_items_total + labor_total + parts_total
  end
  
  def line_items_changed?
    quotation_line_items.any?(&:changed?)
  end
  
  def jobs_changed?
    quotation_jobs.any?(&:changed?)
  end
  
  def update_status_timestamps
    return unless status_changed?
    
    case status.to_sym
    when :sent
      self.sent_at = Time.current if sent_at.nil?
    when :accepted
      self.accepted_at = Time.current if accepted_at.nil?
    when :rejected
      self.rejected_at = Time.current if rejected_at.nil?
    when :converted
      self.converted_at = Time.current if converted_at.nil?
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
    when :sent then 'Sent to Agency'
    when :accepted then 'Accepted'
    when :rejected then 'Rejected'
    when :expired then 'Expired'
    when :converted then 'Converted to PO'
    when :pending_acceptance then 'Pending Acceptance'
    when :partially_rejected then 'Partially Rejected'
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
    when :pending_acceptance then 'warning'
    when :partially_rejected then 'danger'
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
    [:draft, :sent, :pending_acceptance].include?(status.to_sym) && !expired?
  end
  
  def can_be_rejected?
    [:draft, :sent, :accepted, :pending_acceptance].include?(status.to_sym) && !expired?
  end
  
  def can_be_converted_to_po?
    [:accepted, :pending_acceptance].include?(status.to_sym)
  end
  
  def can_be_sent?
    draft? && !expired? && vendor == 'VMCOTT'
  end
  
  def can_be_edited?
    draft? && vendor == 'VMCOTT'
  end
  
  def timeline_events
    events = []
    
    # Creation event
    events << {
      event: 'Quotation Created',
      date: created_at,
      user: created_by,
      description: "Quotation #{quote_number} created",
      icon: 'file-earmark-plus',
      active: true
    }
    
    # Sent event
    if sent? || accepted? || rejected? || converted?
      events << {
        event: 'Sent to Agency',
        date: sent_at || updated_at,
        description: "Quotation sent to requesting agency",
        icon: 'send',
        active: sent_at.present?
      }
    end
    
    # Acceptance event
    if accepted? && accepted_at
      events << {
        event: 'Accepted',
        date: accepted_at,
        description: "Quotation accepted by agency",
        icon: 'check-circle',
        active: true
      }
    end
    
    # Rejection event
    if rejected? && rejected_at
      events << {
        event: 'Rejected',
        date: rejected_at,
        description: "Quotation rejected",
        icon: 'x-circle',
        active: true
      }
    end
    
    # Conversion event
    if converted? && converted_at
      events << {
        event: 'Converted to PO',
        date: converted_at,
        description: "Converted to purchase order",
        icon: 'cart-check',
        active: true
      }
    end
    
    # Expiry event
    if expired? && valid_to
      events << {
        event: 'Expired',
        date: valid_to,
        description: "Quotation validity expired",
        icon: 'clock-history',
        active: true
      }
    end
    
    events.sort_by { |e| e[:date] || Time.at(0) }
  end
  
  # UPDATED: Now uses direct agency association
  def agency_name
    agency&.name || vehicle&.agency&.name || 'Fleet Management'
  end
  
  # UPDATED: Now uses direct agency association
  def agency_code
    agency&.code || vehicle&.agency&.code
  end
  
  # Total labor cost from jobs
  def total_labor_cost
    quotation_jobs.sum(:total_labor_cost).to_f
  end
  
  # Total parts cost from jobs
  def total_parts_cost
    quotation_job_parts.sum(&:total_price).to_f
  end
  
  # Total job cost (labor + parts)
  def total_job_cost
    total_labor_cost + total_parts_cost
  end
  
  # Check if has jobs assigned
  def has_jobs?
    quotation_jobs.any?
  end
  
  # For PDF generation
  def to_pdf
    content = "=" * 60 + "\n"
    content += "QUOTATION\n"
    content += "=" * 60 + "\n\n"
    
    content += "Quotation Details:\n"
    content += "  Quote #: #{quote_number}\n"
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
    
    if quotation_jobs.any?
      content += "Job Details:\n"
      content += "-" * 60 + "\n"
      quotation_jobs.each_with_index do |job, index|
        content += "Job #{index + 1}: #{job.name}\n"
        content += "  Description: #{job.description}\n"
        content += "  Hours: #{job.estimated_hours} @ $#{'%.2f' % job.labor_rate_per_hour}/hr = $#{'%.2f' % job.total_labor_cost}\n"
        
        if job.quotation_job_parts.any?
          content += "  Parts Required:\n"
          job.quotation_job_parts.each do |part|
            content += "    • #{part.part&.name || 'Part'}: #{part.quantity} x $#{'%.2f' % part.unit_price} = $#{'%.2f' % part.total_price}\n"
          end
        end
        content += "\n"
      end
      content += "-" * 60 + "\n"
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
    
    if quotation_jobs.any?
      content += "Job Breakdown:\n"
      content += "  Labor Cost: $#{'%.2f' % total_labor_cost}\n"
      content += "  Parts Cost: $#{'%.2f' % total_parts_cost}\n"
      content += "  Total Job Cost: $#{'%.2f' % total_job_cost}\n\n"
    end
    
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