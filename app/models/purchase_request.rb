# app/models/purchase_request.rb
class PurchaseRequest < ApplicationRecord
  belongs_to :requested_by, class_name: 'User', optional: true
  belongs_to :approved_by, class_name: 'User', optional: true
  belongs_to :part, optional: true
  belongs_to :quotation, optional: true
  
  # Remove validations for columns that don't exist
  # validates :pr_number, presence: true, uniqueness: true  # NO COLUMN
  # validates :request_date, presence: true  # NO COLUMN
  
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
  
  # Add a display name method
  def display_name
    "PR##{id} - #{part&.name || 'Unknown Part'}"
  end
  
  def total_estimated_cost
    quantity.to_i * (part&.cost_price || 0)
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
  
  # Scopes
  scope :pending, -> { where(status: 'pending') }
  scope :approved, -> { where(status: 'approved') }
  scope :needs_ordering, -> { where(status: 'approved').where(ordered_at: nil) }
  scope :needs_receiving, -> { where(status: 'ordered').where(received_at: nil) }
end