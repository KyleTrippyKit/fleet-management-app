# app/models/purchase.rb
class Purchase < ApplicationRecord
  belongs_to :part
  validates :quantity, :supplier, :status, presence: true
end
