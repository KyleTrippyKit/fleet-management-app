# app/models/purchase_order_item.rb
class PurchaseOrderItem < ApplicationRecord
  belongs_to :purchase_order
  belongs_to :part, optional: true

  validates :description, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :unit_price, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Add acceptance fields
  attribute :is_accepted, :boolean, default: true
  
  # Add scopes for acceptance
  scope :accepted, -> { where(is_accepted: true) }
  scope :rejected, -> { where(is_accepted: false) }
  scope :pending_acceptance, -> { where(is_accepted: nil) }

  before_save :calculate_total

  def calculate_total
    self.total_price = quantity * unit_price
  end
  
  def unit_price_formatted
    sprintf('%.2f', unit_price)
  end
  
  def total_price_formatted
    sprintf('%.2f', total_price)
  end
  
  # Get acceptance status for display
  def acceptance_status
    if is_accepted.nil?
      'pending'
    elsif is_accepted
      'accepted'
    else
      'rejected'
    end
  end
  
  # Get acceptance badge class for UI
  def acceptance_badge_class
    case acceptance_status
    when 'accepted'
      'badge bg-success'
    when 'rejected'
      'badge bg-danger'
    when 'pending'
      'badge bg-warning text-dark'
    else
      'badge bg-secondary'
    end
  end
  
  # Get acceptance text for display
  def acceptance_text
    case acceptance_status
    when 'accepted'
      '✓ Accepted'
    when 'rejected'
      '✗ Rejected'
    when 'pending'
      '⏳ Pending'
    else
      'Not Reviewed'
    end
  end
end