# app/models/job_template_part.rb
class JobTemplatePart < ApplicationRecord
  belongs_to :job_template
  belongs_to :part
  
  validates :quantity, numericality: { greater_than: 0 }
  validates :job_template_id, uniqueness: { scope: :part_id }
end