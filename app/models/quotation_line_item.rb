class QuotationLineItem < ApplicationRecord
  belongs_to :quotation
  
  validates :description, presence: true
  validates :quantity, numericality: { greater_than: 0 }, allow_nil: true
  validates :unit_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  
  before_validation :set_defaults
  
  def total_price
    (quantity || 0) * (unit_price || 0)
  end
  
  def formatted_unit_price
    ActionController::Base.helpers.number_to_currency(unit_price || 0, unit: "$")
  end
  
  def formatted_total_price
    ActionController::Base.helpers.number_to_currency(total_price, unit: "$")
  end
  
  private
  
  def set_defaults
    self.quantity ||= 1
    self.unit_price ||= 0
  end
end