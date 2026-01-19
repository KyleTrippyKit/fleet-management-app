# app/models/purchase_order_item.rb
class PurchaseOrderItem < ApplicationRecord
  belongs_to :purchase_order
  belongs_to :part, optional: true

  validates :description, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :unit_price, presence: true, numericality: { greater_than_or_equal_to: 0 }

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
end