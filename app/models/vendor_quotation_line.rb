# app/models/vendor_quotation_line.rb
class VendorQuotationLine < ApplicationRecord
  belongs_to :vendor_quotation
  belongs_to :part, optional: true  # Make part optional for custom parts

  before_validation :compute_total

  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  
  # Add validation to ensure either part_id or description is present
  validate :must_have_part_or_description

  def compute_total
    q = quantity.to_f
    p = unit_price.to_f
    self.total_price = (q * p).round(2)
  end
  
  def part_name
    return part.name if part.present?
    description.to_s
  end
  
  def custom?
    part_id.nil?
  end

  private

  def must_have_part_or_description
    if part_id.blank? && description.blank?
      errors.add(:base, "Either a part or description must be specified")
    end
  end
end