# app/models/part.rb - FIXED VERSION
class Part < ApplicationRecord
  has_many :purchases
  has_many :maintenance_parts
  has_many :maintenances, through: :maintenance_parts
  has_many :purchase_order_items
  
  # Only validate columns that actually exist in the database
  validates :name, presence: true
  
  # If you want stock_quantity, you need to add a migration for it
  # For now, remove the stock_quantity validation since the column doesn't exist
end