# app/models/parts_request_item.rb
class PartsRequestItem < ApplicationRecord
  belongs_to :parts_request
  belongs_to :part
  
  validates :quantity_needed, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: ['in_stock', 'needs_purchase', 'ordered', 'received'] }
  
  def received?
    status == 'received'
  end
  
  def total_cost
    return 0 unless received? && part.present?
    part.cost_price * quantity_needed
  end
end