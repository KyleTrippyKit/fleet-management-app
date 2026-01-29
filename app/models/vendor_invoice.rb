class VendorInvoice < ApplicationRecord
  belongs_to :supplier
  belongs_to :purchase_order, optional: true
  belongs_to :user, optional: true
  has_many :inventory_transactions
  has_many :purchase_requests
  has_many :vendor_invoice_items, dependent: :destroy
  accepts_nested_attributes_for :vendor_invoice_items, allow_destroy: true
  
  has_one_attached :invoice_scan
  
  validates :invoice_number, presence: true, uniqueness: true
  validates :invoice_date, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  
  # Rails 8+ enum syntax
  enum :status, {
    pending: 'pending',
    reviewed: 'reviewed',
    paid: 'paid',
    disputed: 'disputed',
    cancelled: 'cancelled'
  }
  
  # Add validations for file
  validate :validate_invoice_scan
  
  def validate_invoice_scan
    return unless invoice_scan.attached?
    
    # Validate file type
    allowed_types = ['image/jpeg', 'image/png', 'image/gif', 'application/pdf']
    unless allowed_types.include?(invoice_scan.content_type)
      errors.add(:invoice_scan, 'must be a JPEG, PNG, GIF, or PDF file')
    end
    
    # Validate file size (max 10MB)
    if invoice_scan.byte_size > 10.megabytes
      errors.add(:invoice_scan, 'size must be less than 10MB')
    end
  end
  
  # Calculate due date if not set
  before_save :set_due_date
  def set_due_date
    self.due_date ||= invoice_date + 30.days if invoice_date
  end
  
  # Calculate amount from items
  def update_amount_from_items
    self.amount = vendor_invoice_items.sum(:total_price)
    save
  end
  
  # Link to purchase order items
  def link_to_purchase_order_items
    return unless purchase_order.present?
    
    vendor_invoice_items.each do |invoice_item|
      next unless invoice_item.part.present?
      
      po_item = purchase_order.purchase_order_items.find_by(part_id: invoice_item.part_id)
      invoice_item.update(purchase_order_item: po_item) if po_item
    end
  end
  
  # Scopes
  scope :search, ->(query = nil) {
    return all if query.blank?
    where("invoice_number ILIKE ? OR description ILIKE ?", 
          "%#{query}%", "%#{query}%")
  }
  
  scope :by_date_range, ->(start_date, end_date) {
    where(invoice_date: start_date..end_date)
  }
  
  scope :overdue, -> {
    where("due_date < ? AND status IN (?)", Date.today, ['pending', 'reviewed'])
  }
  
  scope :by_supplier, ->(supplier_id) {
    where(supplier_id: supplier_id)
  }
  
  # Days overdue
  def days_overdue
    return 0 if paid? || due_date.nil? || due_date >= Date.today
    (Date.today - due_date).to_i
  end
  
  # Aging bucket
  def aging_bucket
    return 'current' if !due_date || due_date >= Date.today
    days = days_overdue
    
    case days
    when 0..30 then '1-30 days'
    when 31..60 then '31-60 days'
    when 61..90 then '61-90 days'
    else '90+ days'
    end
  end
  
  # Process payment
  def mark_as_paid(payment_date = Date.today, notes = nil)
    update!(
      status: :paid,
      paid_date: payment_date,
      payment_notes: notes
    )
  end
end