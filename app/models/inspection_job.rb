# app/models/inspection_job.rb
class InspectionJob < ApplicationRecord
  belongs_to :inspection
  belongs_to :job_template, optional: true
  belongs_to :assigned_mechanic, class_name: 'User', optional: true
  
  PRIORITIES = ['low', 'normal', 'high', 'critical'].freeze
  
  validates :description, presence: true
  validates :priority, inclusion: { in: PRIORITIES }, allow_nil: true
  
  scope :pending, -> { where(completed_at: nil) }
  scope :completed, -> { where.not(completed_at: nil) }
  scope :by_priority, -> { order(Arel.sql("CASE priority WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'normal' THEN 2 ELSE 3 END")) }
  
  def estimated_total
    estimated_labor_cost.to_f + estimated_parts_cost.to_f
  end
  
  def completed?
    completed_at.present?
  end
  
  def priority_badge_color
    case priority
    when 'critical' then 'danger'
    when 'high' then 'warning'
    when 'normal' then 'info'
    else 'secondary'
    end
  end
  
  def assign_to_mechanic(mechanic_user)
    update(assigned_mechanic: mechanic_user, assigned_at: Time.current)
  end
  
  def complete!(completion_notes = nil)
    update(completed_at: Time.current, completion_notes: completion_notes)
  end
  
  def create_internal_po
    return unless inspection.purchase_order.present?
    
    inspection.purchase_order.internal_pos.create!(
      work_order_number: InternalPos.generate_work_order_number,
      created_by: assigned_mechanic,
      status: 'pending',
      priority: priority,
      notes: "[Work Section: Workshop]\n[Work Role: Technician]\n#{description}\n\nFrom Inspection Job ##{id}"
    )
  end
end