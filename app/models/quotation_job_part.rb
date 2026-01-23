# app/models/quotation_job_part.rb
class QuotationJobPart < ApplicationRecord
  belongs_to :quotation_job
  belongs_to :part
  
  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price, numericality: { greater_than_or_equal_to: 0 }
  validates :quotation_job_id, uniqueness: { scope: :part_id }
  
  before_save :calculate_total_price
  
  private
  
  def calculate_total_price
    self.total_price = quantity * (unit_price || 0)
  end
end