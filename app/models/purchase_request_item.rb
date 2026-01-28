class PurchaseRequestItem < ApplicationRecord
  belongs_to :purchase_request
  belongs_to :part
  
  validates :quantity_requested, numericality: { greater_than: 0 }
end