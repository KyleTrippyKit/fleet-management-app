class MaintenancePart < ApplicationRecord
  belongs_to :maintenance
  belongs_to :part
end
