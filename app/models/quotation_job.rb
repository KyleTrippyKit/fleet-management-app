# app/models/quotation_job.rb
class QuotationJob < ApplicationRecord
  # Associations
  belongs_to :quotation
  belongs_to :job_template, optional: true
  
  has_many :quotation_job_parts, dependent: :destroy
  has_many :parts, through: :quotation_job_parts
  
  accepts_nested_attributes_for :quotation_job_parts, allow_destroy: true
  
  # Validations
  validates :name, presence: true
  validates :job_type, presence: true
  # validates :quotation_id, presence: true
  
  # Comment out the enum for now to see if that's the issue
  # enum job_type: {
  #   template: 'template',
  #   custom: 'custom'
  # }
  
  before_save :calculate_labor_cost
  
  # Instance methods
  def calculate_labor_cost
    if estimated_hours.present? && labor_rate_per_hour.present?
      self.total_labor_cost = estimated_hours * labor_rate_per_hour
    end
  end
  
  def total_parts_cost
    quotation_job_parts.sum(:total_price)
  end
  
  def total_job_cost
    (total_labor_cost || 0) + (total_parts_cost || 0)
  end
  
  private
  
  # If you have any other private methods, add them here
end