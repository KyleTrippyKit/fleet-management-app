# app/models/part.rb
class Part < ApplicationRecord
  has_many :purchases
  validates :name, :stock_quantity, presence: true
end
