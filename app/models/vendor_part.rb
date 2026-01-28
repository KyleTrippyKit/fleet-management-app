# app/models/vendor_part.rb - NEW FILE
class VendorPart < ApplicationRecord
  belongs_to :supplier
  belongs_to :part
  
  validates :supplier_id, uniqueness: { scope: :part_id }
  
  scope :preferred, -> { where(is_preferred: true) }
  scope :active, -> { where(is_active: true) }
  
  # Search parts by vendor
  def self.search_parts(supplier_id, query)
    joins(:part).where(supplier_id: supplier_id).where(
      "parts.name ILIKE ? OR parts.part_number ILIKE ? OR vendor_part_number ILIKE ?",
      "%#{query}%", "%#{query}%", "%#{query}%"
    )
  end
end