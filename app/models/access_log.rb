class AccessLog < ApplicationRecord
  belongs_to :user
  belongs_to :agency
  
  # Map your controller's method to use existing columns
  # Or add methods to adapt the data
end