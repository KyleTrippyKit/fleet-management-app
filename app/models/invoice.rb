class Invoice < ApplicationRecord
  # Associations - ONLY associations that exist in your database
  belongs_to :vehicle, optional: true
  belongs_to :maintenance, optional: true
  
  # Note: Remove these associations until you create the database columns
  # belongs_to :created_by, class_name: 'User', optional: true
  # belongs_to :received_by, class_name: 'User', optional: true
  # belongs_to :paid_by, class_name: 'User', optional: true
  
  # Validations
  validates :invoice_number, presence: true, uniqueness: true
  validates :vendor, presence: true
  validates :invoice_date, :due_date, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  
  # Enums - Use simpler statuses that match your database
  # Your database has default: "pending" so we need to match that
  enum :status, {
    pending: 'pending',
    paid: 'paid', 
    overdue: 'overdue',
    cancelled: 'cancelled'
  }
  
  # Set default status to match your database schema
  after_initialize :set_default_status, if: :new_record?
  
  # Scopes
  scope :overdue, -> { where('due_date < ? AND status = ?', Date.today, 'pending') }
  
  scope :by_service_owner, ->(owner) { 
    if owner.present?
      joins(:vehicle).where(vehicles: { service_owner: owner })
    else
      all
    end
  }
  
  # Search
  def self.search(query)
    return all if query.blank?
    
    where(
      "invoice_number ILIKE :q OR vendor ILIKE :q",
      q: "%#{query}%"
    )
  end
  
  # Status badge helper for views
  def status_badge_class
    case status
    when 'paid'
      'bg-success'
    when 'pending'
      'bg-warning text-dark'
    when 'overdue'
      'bg-danger'
    when 'cancelled'
      'bg-secondary'
    else
      'bg-info'
    end
  end
  
  # Get service owner from vehicle
  def service_owner
    vehicle&.service_owner
  end
  
  # Get agency name (alias for service_owner)
  def agency
    service_owner
  end
  
  # Days until due (negative if overdue)
  def days_until_due
    return nil unless due_date
    (due_date - Date.today).to_i
  end
  
  # Check if invoice is overdue
  def overdue?
    pending? && due_date.present? && due_date < Date.today
  end
  
  # Get agency name for display
  def agency_name
    service_owner || 'Unknown Agency'
  end
  
  # Get vehicle display info
  def vehicle_display
    return 'No vehicle assigned' unless vehicle
    "#{vehicle.license_plate} - #{vehicle.make} #{vehicle.model}"
  end
  
  # Calculate aging (days since invoice date)
  def aging_days
    return nil unless invoice_date
    (Date.today - invoice_date).to_i
  end
  
  # Simple mark as paid method
  def mark_as_paid
    update(status: 'paid')
  end
  
  # Simple mark as reviewed method
  def mark_as_reviewed
    update(status: 'pending') # Your schema only has 'pending', not 'pending_review'/'pending_payment'
  end
  
  # Simple mark as disputed method
  def mark_as_disputed(reason = nil)
    update(
      status: 'cancelled', # Using cancelled for disputed since you don't have disputed status
      notes: [notes, "Disputed: #{reason}"].compact.join("\n\n")
    )
  end
  
  # Callbacks
  before_save :update_status_based_on_due_date
  
  private
  
  def set_default_status
    self.status ||= 'pending'
  end
  
  def update_status_based_on_due_date
    if pending? && due_date.present? && due_date < Date.today
      self.status = 'overdue'
    end
  end
end