# app/models/vendor_quotation_line.rb
class VendorQuotationLine < ApplicationRecord
  belongs_to :vendor_quotation
  belongs_to :part

  before_validation :compute_total

  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  def compute_total
    q = quantity.to_f
    p = unit_price.to_f
    self.total_price = (q * p).round(2)
  end
end
