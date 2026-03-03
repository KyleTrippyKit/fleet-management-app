# app/models/vendor_rfq_item.rb
class VendorRfqItem < ApplicationRecord
  belongs_to :vendor_rfq
  belongs_to :part, optional: true  # Make part optional for custom parts

  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_of_measure, presence: true
  
  # Ensure either part_id or custom_part_name is present
  validate :must_have_part_or_custom_name

  def display_name
    return part.display_name if part.present?
    return custom_part_name if custom_part_name.present?
    description.to_s
  end

  def part_name
    return part.name if part.present?
    return custom_part_name if custom_part_name.present?
    description.to_s
  end

  def part_number
    part&.part_number
  end

  def custom?
    part_id.nil?
  end

  private

  def must_have_part_or_custom_name
    if part_id.blank? && custom_part_name.blank?
      errors.add(:base, "Either a part or custom part name must be specified")
    end
  end
end