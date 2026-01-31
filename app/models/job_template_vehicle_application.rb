# app/models/job_template_vehicle_application.rb
class JobTemplateVehicleApplication < ApplicationRecord
  belongs_to :job_template

  validates :make, :model, :year, presence: true
  validates :year, numericality: { only_integer: true, greater_than: 1900, less_than: 2100 }
end
