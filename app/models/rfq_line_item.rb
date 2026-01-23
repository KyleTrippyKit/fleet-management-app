# app/models/rfq_line_item.rb
class RfqLineItem < ApplicationRecord
  belongs_to :rfq
  
  validates :description, presence: true
  validates :quantity, numericality: { greater_than: 0 }
  
  # FIXED: Correct enum syntax
  enum :category, {
    parts: 'parts',
    labor: 'labor',
    other: 'other'
  }, default: :parts
end