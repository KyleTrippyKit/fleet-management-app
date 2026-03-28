class Payment < ApplicationRecord
  belongs_to :inspection
  belongs_to :work_order, optional: true
end
