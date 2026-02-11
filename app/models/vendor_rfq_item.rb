# app/models/vendor_rfq_item.rb
class VendorRfqItem < ApplicationRecord
  belongs_to :vendor_rfq
  belongs_to :part

  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_of_measure, presence: true

  def display_name
    part&.display_name || description.to_s
  end
end
