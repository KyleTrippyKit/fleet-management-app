# app/models/quotation_job_part.rb
class QuotationJobPart < ApplicationRecord
  belongs_to :quotation_job
  belongs_to :part, optional: true  # ← ADD optional: true to allow custom parts
  
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :unit_price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :quotation_job_id, presence: true
  
  # Only validate uniqueness if part_id is present
  validates :quotation_job_id, uniqueness: { scope: :part_id }, if: -> { part_id.present? }
  
  # Custom validation: either part_id OR custom_part_name must be present
  validate :either_part_or_custom_name
  
  before_save :calculate_total_price
  
  # Calculate total price for this line item
  def total_price_calculated
    (quantity || 0) * (unit_price || 0)
  end
  
  def part_name
    part&.name || custom_part_name || "Custom Part"
  end
  
  def inventory?
    part_id.present?
  end
  
  def custom?
    part_id.nil?
  end
  
  private
  
  def calculate_total_price
    self.total_price = (quantity || 0) * (unit_price || 0) if respond_to?(:total_price=)
  end
  
  def either_part_or_custom_name
    if part_id.blank? && custom_part_name.blank?
      errors.add(:base, "Either a part must be selected or a custom part name must be provided")
    end
  end
end