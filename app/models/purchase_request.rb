# app/models/purchase_request.rb
class PurchaseRequest < ApplicationRecord
  belongs_to :requested_by, class_name: 'User', optional: true
  belongs_to :approved_by, class_name: 'User', optional: true
  belongs_to :part, optional: true
  belongs_to :quotation, optional: true
  
  has_many :purchase_request_items, dependent: :destroy
  
  # Rails 8.1 enum syntax
  enum :status, {
    pending: 'pending',
    approved: 'approved',
    rejected: 'rejected',
    ordered: 'ordered',
    received: 'received',
    cancelled: 'cancelled'
  }, default: :pending
  
  enum :urgency, {
    low: 'low',
    normal: 'normal',
    high: 'high',
    critical: 'critical'
  }, default: :normal
  
  # Validations
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :urgency, presence: true
  validates :status, presence: true
  
  # Add a display name method
  def display_name
    "PR##{id} - #{part&.name || 'Unknown Part'}"
  end
  
  # Generate PR number - Option 2
  def pr_number
    # If there's already a pr_number column, use it
    return self[:pr_number] if has_attribute?(:pr_number) && self[:pr_number].present?
    
    # Otherwise generate a consistent PR number
    "PR-#{created_at&.strftime('%Y%m%d') || Time.now.strftime('%Y%m%d')}-#{id.to_s.rjust(4, '0')}"
  end
  
  # For backward compatibility and form fields
  def pr_number=(value)
    if has_attribute?(:pr_number)
      self[:pr_number] = value
    end
  end
  
  def total_estimated_cost
    quantity.to_i * (part&.cost_price || 0)
  end
  
  # Status badge color helpers
  def status_badge_color
    case status
    when 'approved' then 'success'
    when 'rejected' then 'danger'
    when 'pending' then 'warning'
    when 'ordered' then 'info'
    when 'received' then 'secondary'
    when 'cancelled' then 'dark'
    else 'secondary'
    end
  end
  
  # Urgency badge color helpers
  def urgency_badge_color
    case urgency
    when 'critical' then 'danger'
    when 'high' then 'warning'
    when 'normal' then 'primary'
    when 'low' then 'secondary'
    else 'secondary'
    end
  end
  
  # Check if request is overdue
  def overdue?
    return false unless needed_by_date.present?
    needed_by_date < Date.today && !['received', 'cancelled'].include?(status)
  end
  
  # Check if request is due soon (within 3 days)
  def due_soon?
    return false unless needed_by_date.present?
    needed_by_date <= Date.today + 3.days && needed_by_date >= Date.today && !['received', 'cancelled'].include?(status)
  end
  
  # Timestamp methods
  def approve!(user)
    update(
      status: :approved,
      approved_by: user,
      approved_at: Time.current
    )
  end
  
  def mark_ordered!
    update(status: :ordered, ordered_at: Time.current)
  end
  
  def mark_received!
    update(status: :received, received_at: Time.current)
  end
  
  def reject!(user, reason = nil)
    update(
      status: :rejected,
      rejected_by: user,
      rejected_at: Time.current,
      notes: notes.to_s + "\nRejection reason: #{reason}"
    )
  end
  
  # Status check methods
  def pending?
    status == 'pending'
  end
  
  def approved?
    status == 'approved'
  end
  
  def ordered?
    status == 'ordered'
  end
  
  def received?
    status == 'received'
  end
  
  def rejected?
    status == 'rejected'
  end
  
  # Items management
  def items
    purchase_request_items
  end
  
  def add_item(part, quantity, reason = nil)
    purchase_request_items.create(
      part: part,
      quantity_requested: quantity,
      reason: reason
    )
  end
  
  # For forms and APIs
  def part_id=(value)
    self.part = Part.find_by(id: value)
  end
  
  def requested_by_id=(value)
    self.requested_by = User.find_by(id: value)
  end
  
  # Scopes
  scope :pending, -> { where(status: 'pending') }
  scope :approved, -> { where(status: 'approved') }
  scope :needs_ordering, -> { where(status: 'approved').where(ordered_at: nil) }
  scope :needs_receiving, -> { where(status: 'ordered').where(received_at: nil) }
  scope :overdue, -> { 
    where('needed_by_date < ?', Date.today)
    .where.not(status: ['received', 'cancelled'])
  }
  scope :due_soon, -> {
    where('needed_by_date <= ? AND needed_by_date >= ?', Date.today + 3.days, Date.today)
    .where.not(status: ['received', 'cancelled'])
  }
  
  # Search scope
  scope :search, ->(query) {
    if query.present?
      left_joins(:part)
        .where("purchase_requests.id::text ILIKE ? OR 
                parts.name ILIKE ? OR 
                parts.part_number ILIKE ? OR 
                purchase_requests.notes ILIKE ?",
               "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%")
    end
  }
  
  # Callbacks
  before_create :set_defaults, if: :new_record?
  
  private
  
  def set_defaults
    self.status ||= 'pending'
    self.urgency ||= 'normal'
    self.requested_by ||= User.current if defined?(User.current)
  end
end