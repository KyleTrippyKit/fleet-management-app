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
  validate :cannot_add_parts_after_approval, if: :approved_for_repair?

  scope :pending, -> { where(completed_at: nil) }
  scope :completed, -> { where.not(completed_at: nil) }
  scope :by_priority, -> { order(Arel.sql("CASE priority WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'normal' THEN 2 ELSE 3 END")) }

  def estimated_total
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
  
  def has_custom_parts?
    inspection_job_parts.any?(&:custom?)
  end
  
  def all_parts
    inspection_job_parts.map(&:part_name).join(', ')
  end

  def approved_for_repair?
    inspection&.status == 'approved_for_repair'
  end

  def cannot_add_parts_after_approval
    if inspection&.status == 'approved_for_repair' && will_save_change_to_parts?
      errors.add(:base, "Cannot add parts after job is approved. Create additional work request instead.")
    end
  end

  def lock_for_changes!
    update!(locked_for_changes: true, locked_at: Time.current)
  end

  def record_parts_usage!
    # Only record usage when job is completed
    if completed? && !locked_for_changes?
      total_quantity = inspection_job_parts.sum(:quantity)
      update!(
        quantity_used: total_quantity,
        locked_for_changes: true,
        locked_at: Time.current
      )
    end
  end
end