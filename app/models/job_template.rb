# app/models/job_template.rb
class JobTemplate < ApplicationRecord
  belongs_to :agency
  has_many :job_template_parts, dependent: :destroy
  has_many :parts, through: :job_template_parts
  has_many :quotation_jobs
  
  validates :name, presence: true, uniqueness: { scope: :agency_id }
  validates :agency_id, presence: true
  
  scope :active, -> { where(is_active: true) }
  scope :by_category, ->(category) { where(category: category) }
  
  def labor_cost(rate_per_hour = nil)
    rate = rate_per_hour || labor_rate_per_hour || agency.standard_labor_rate
    (standard_hours || 0) * (rate || 0)
  end
  
  def total_parts_cost
    job_template_parts.joins(:part).sum('parts.price * job_template_parts.quantity')
  end
end