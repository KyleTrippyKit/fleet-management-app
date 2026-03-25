# app/models/inspection_job.rb
class InspectionJob < ApplicationRecord
  include Auditable
  
  belongs_to :inspection
  belongs_to :job_template, optional: true
  belongs_to :assigned_mechanic, class_name: 'User', optional: true

  has_many :inspection_job_parts, dependent: :destroy
  has_many :parts, through: :inspection_job_parts
  has_many :mechanic_assignments, dependent: :destroy
  has_many :parts_requests, foreign_key: :inspection_job_id, dependent: :nullify
  has_many :findings, dependent: :destroy
  
  # Job dependencies
  has_many :dependencies_as_job, class_name: 'JobDependency', foreign_key: :job_id, dependent: :destroy
  has_many :dependencies_on, through: :dependencies_as_job, source: :depends_on
  
  has_many :dependencies_as_dependency, class_name: 'JobDependency', foreign_key: :depends_on_job_id, dependent: :destroy
  has_many :dependent_jobs, through: :dependencies_as_dependency, source: :job

  PRIORITIES = ['low', 'normal', 'high', 'critical'].freeze

  # Status workflow - NEW status for supervisor review
  enum :status, {
    pending_supervisor_review: 'pending_supervisor_review',  # NEW - waiting for supervisor to set pricing
    pending_mechanic_review: 'pending_mechanic_review',
    pending_parts_review: 'pending_parts_review',
    approved: 'approved',
    pending_mechanic_work: 'pending_mechanic_work',
    in_progress: 'in_progress',
    paused: 'paused',
    blocked: 'blocked',
    rework_needed: 'rework_needed',
    completed: 'completed'
  }, default: :pending_supervisor_review  # Changed default

  # Add new fields
  attribute :paused_at, :datetime
  attribute :paused_reason, :text
  attribute :blocked_at, :datetime
  attribute :blocked_reason, :text
  attribute :rework_requested_at, :datetime
  attribute :rework_reason, :text
  attribute :actual_labor_cost, :decimal, precision: 10, scale: 2
  attribute :actual_parts_cost, :decimal, precision: 10, scale: 2
  attribute :started_at, :datetime
  attribute :assigned_at, :datetime
  attribute :completed_at, :datetime
  attribute :locked_for_changes, :boolean, default: false
  attribute :locked_at, :datetime
  attribute :quantity_used, :integer, default: 0

  validates :description, presence: true
  validates :priority, inclusion: { in: PRIORITIES }, allow_nil: true
  validate :cannot_add_parts_after_approval, if: :approved_for_repair?

  # Scopes
  scope :pending, -> { where(completed_at: nil) }
  scope :completed, -> { where.not(completed_at: nil) }
  scope :by_priority, -> { order(Arel.sql("CASE priority WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'normal' THEN 2 ELSE 3 END")) }
  scope :available_for_work, -> { where(status: :pending_mechanic_work) }
  scope :in_progress, -> { where(status: :in_progress) }
  scope :paused, -> { where(status: :paused) }
  scope :blocked, -> { where(status: :blocked) }
  scope :rework_needed, -> { where(status: :rework_needed) }
  scope :needs_supervisor_pricing, -> { where(status: :pending_supervisor_review) }

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

  def can_start?
    puts "DEBUG: can_start? called - status: #{status}, dependencies: #{dependencies_on.map(&:status)}"
    puts "DEBUG: can_start? called - status: #{status}, client_can_start_work?: #{inspection.client_can_start_work?}"
    return false unless status == 'pending_mechanic_work'
    return false unless inspection.client_can_start_work?
    
    unless dependencies_satisfied?
      puts "DEBUG: can_start? failed - missing dependencies: #{missing_dependencies.map(&:id)}"
      return false
    end
    
    if blocked?
      puts "DEBUG: can_start? failed - job is blocked: #{blocked_reason}"
      return false
    end
    
    true
  end

  def can_pause?
    status == 'in_progress'
  end

  def can_resume?
    status == 'paused'
  end

  def can_complete?
    status == 'in_progress'
  end

  def start!
    puts ">>> DEBUG: In start! method for job #{id}"
    puts "DEBUG: In start! method - current status: #{status}"
    update!(
      status: :in_progress,
      started_at: Time.current
    )
  end

  def pause!(reason)
    update!(
      status: :paused,
      paused_at: Time.current,
      paused_reason: reason
    )
  end

  def resume!
    update!(
      status: :in_progress,
      paused_at: nil,
      paused_reason: nil
    )
  end

  def block!(reason, requires_quote: true)
    update!(
      status: :blocked,
      blocked_at: Time.current,
      blocked_reason: reason
    )
    
    if requires_quote && inspection.present?
      inspection.findings.create!(
        inspection_job: self,
        finding_type: 'mechanic',
        description: reason,
        severity: 'critical',
        blocking: true,
        created_by_id: Current.user&.id
      )
    end
  end

  def complete!(actual_cost = nil)
    update!(
      status: :completed,
      completed_at: Time.current,
      actual_labor_cost: actual_cost || estimated_labor_cost,
      quantity_used: inspection_job_parts.sum(:quantity),
      locked_for_changes: true,
      locked_at: Time.current
    )
    
    inspection_job_parts.each do |job_part|
      job_part.record_usage! if job_part.respond_to?(:record_usage!)
    end
  end

  def request_rework!(reason)
    update!(
      status: :rework_needed,
      rework_requested_at: Time.current,
      rework_reason: reason
    )
  end

  def add_dependency(dependency_job, type: 'required')
    dependencies_as_job.create!(
      depends_on_job_id: dependency_job.id,
      dependency_type: type
    )
  end

  def missing_dependencies
    dependencies_on.where.not(status: 'completed')
  end

  def dependencies_satisfied?
    missing_dependencies.empty?
  end

  def cannot_add_parts_after_approval
    if inspection&.status == 'approved_for_repair' && will_save_change_to_parts?
      errors.add(:base, "Cannot add parts after job is approved. Create additional work request instead.")
    end
  end

  def lock_for_changes!
    update!(locked_for_changes: true, locked_at: Time.current)
  end

  def unlock_for_changes!
    update!(locked_for_changes: false, locked_at: nil)
  end

  def record_parts_usage!
    if completed? && !locked_for_changes?
      total_quantity = inspection_job_parts.sum(:quantity)
      update!(
        quantity_used: total_quantity,
        locked_for_changes: true,
        locked_at: Time.current
      )
    end
  end

  def change_log
    if defined?(PaperTrail) && has_paper_trail?
      versions.order(created_at: :desc)
    else
      []
    end
  end

  private

  def will_save_change_to_parts?
    inspection_job_parts.any?(&:changed?) || inspection_job_parts.any?(&:new_record?)
  end
end