class PurchaseOrder < ApplicationRecord
  belongs_to :vehicle, optional: true
  belongs_to :created_by, class_name: 'User'
  belongs_to :approved_by, class_name: 'User', optional: true
  has_many :invoices
  
  enum :status, {
    draft: 0,
    pending_approval: 1,
    approved: 2,
    rejected: 3,
    completed: 4,
    cancelled: 5
  }, default: :draft
  
  validates :po_number, presence: true, uniqueness: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :vendor, presence: true
  
  scope :active, -> { where(status: [:approved, :pending_approval]) }
  scope :pending, -> { where(status: :pending_approval) }
  scope :approved, -> { where(status: :approved) }
  
  before_validation :generate_po_number, on: :create
  
  def generate_po_number
    self.po_number ||= "PO-#{Time.now.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
  end
  
  def approve!(user)
    update(
      status: :approved, 
      approved_by: user, 
      approved_at: Time.current
    )
  end
  
  def reject!(reason = nil)
    update(
      status: :rejected,
      notes: [notes, "Rejected on #{Date.today}: #{reason}"].compact.join("\n\n")
    )
  end
  
  def total_invoiced
    invoices.sum(:amount)
  end
  
  def remaining_balance
    amount - total_invoiced
  end
  
  def completion_percentage
    return 0 if amount.zero?
    ((total_invoiced / amount) * 100).round(2)
  end
  
  def display_status
    status.humanize
  end
end