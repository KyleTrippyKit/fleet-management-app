# app/models/inspection_job.rb
class InspectionJob < ApplicationRecord
  belongs_to :inspection
  belongs_to :job_template, optional: true
  belongs_to :assigned_mechanic, class_name: 'User', optional: true

  has_many :inspection_job_parts, dependent: :destroy
  has_many :parts, through: :inspection_job_parts
  has_many :mechanic_assignments, dependent: :destroy

  PRIORITIES = ['low', 'normal', 'high', 'critical'].freeze

  validates :description, presence: true
  validates :priority, inclusion: { in: PRIORITIES }, allow_nil: true

  scope :pending, -> { where(completed_at: nil) }
  scope :completed, -> { where.not(completed_at: nil) }
  scope :by_priority, -> { order(Arel.sql("CASE priority WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'normal' THEN 2 ELSE 3 END")) }

  def estimated_total
    # Only labor, parts are handled separately
    estimated_labor_cost.to_f
  end

  def completed?
    completed_at.present?
  end

  def assign_to_mechanic(mechanic_user)
    update(assigned_mechanic: mechanic_user, assigned_at: Time.current)
    mechanic_assignments.create!(mechanic: mechanic_user, status: 'assigned')
  end

  def parts_approved?
    inspection_job_parts.all?(&:customer_approved)
  end
  
  # Helper method to check if job has any custom parts
  def has_custom_parts?
    inspection_job_parts.any?(&:custom?)
  end
  
  # Helper method to get all parts (both inventory and custom)
  def all_parts
    inspection_job_parts.map(&:part_name).join(', ')
  end
end