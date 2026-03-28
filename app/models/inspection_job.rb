# app/models/inspection_job.rb
class InspectionJob < ApplicationRecord
  include Auditable
  
  belongs_to :inspection
  belongs_to :job_template, optional: true
  belongs_to :assigned_mechanic, class_name: 'User', optional: true
  belongs_to :work_order, optional: true  # NEW: Link to work order
  belongs_to :pre_check_by, class_name: 'User', optional: true  # NEW: Who did pre-check
  
  has_many :inspection_job_parts, dependent: :destroy
  has_many :parts, through: :inspection_job_parts
  has_many :mechanic_assignments, dependent: :destroy
  has_many :parts_requests, foreign_key: :inspection_job_id, dependent: :nullify
  has_many :findings, dependent: :destroy
  has_many :job_tasks, dependent: :destroy  # NEW: Tasks for this job
  
  # Job dependencies
  has_many :dependencies_as_job, class_name: 'JobDependency', foreign_key: :job_id, dependent: :destroy
  has_many :dependencies_on, through: :dependencies_as_job, source: :depends_on
  
  has_many :dependencies_as_dependency, class_name: 'JobDependency', foreign_key: :depends_on_job_id, dependent: :destroy
  has_many :dependent_jobs, through: :dependencies_as_dependency, source: :job

  PRIORITIES = ['low', 'normal', 'high', 'critical'].freeze

  # Status workflow - ENHANCED with pre-check and approval stages
  enum :status, {
    pending_supervisor_review: 'pending_supervisor_review',
    pending_mechanic_review: 'pending_mechanic_review',
    pending_parts_review: 'pending_parts_review',
    approved: 'approved',
    assigned: 'assigned',                    # NEW: Assigned to mechanic but not started
    pre_check_in_progress: 'pre_check_in_progress',  # NEW: Mechanic doing pre-check
    pre_check_completed: 'pre_check_completed',      # NEW: Pre-check done, awaiting approval
    pending_approval: 'pending_approval',            # NEW: Waiting for supervisor approval
    approved_for_work: 'approved_for_work',          # NEW: Approved to start work
    pending_mechanic_work: 'pending_mechanic_work',
    in_progress: 'in_progress',
    paused: 'paused',
    blocked: 'blocked',
    rework_needed: 'rework_needed',
    completed: 'completed'
  }, default: :pending_supervisor_review

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
  
  # NEW: Time tracking and pre-check fields
  attribute :total_time_hours, :decimal, precision: 5, scale: 2, default: 0
  attribute :billable_time_hours, :decimal, precision: 5, scale: 2, default: 0
  attribute :pre_check_notes, :text
  attribute :pre_check_completed_at, :datetime
  attribute :additional_findings, :jsonb, default: []
  attribute :pre_check_started_at, :datetime

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
  scope :needs_pre_check, -> { where(status: :assigned) }
  scope :pre_check_in_progress, -> { where(status: :pre_check_in_progress) }
  scope :needs_approval, -> { where(status: :pre_check_completed) }
  
  # NEW: Scopes for work order integration
  scope :by_work_order, ->(work_order_id) { where(work_order_id: work_order_id) }
  scope :with_active_tasks, -> { joins(:job_tasks).where(job_tasks: { status: ['in_progress', 'pending', 'approved'] }).distinct }

  def estimated_total
    estimated_labor_cost.to_f
  end

  def completed?
    completed_at.present?
  end

  def assign_to_mechanic(mechanic_user)
    update(
      assigned_mechanic: mechanic_user, 
      assigned_at: Time.current,
      status: :assigned
    )
    mechanic_assignments.create!(mechanic: mechanic_user, status: 'assigned')
  end

  # =====================================================
  # PRE-CHECK METHODS
  # =====================================================
  
  def start_pre_check!(mechanic)
    update!(
      status: :pre_check_in_progress,
      pre_check_by: mechanic,
      pre_check_started_at: Time.current
    )
  end
  
  def complete_pre_check!(notes, findings = [])
    update!(
      status: :pre_check_completed,
      pre_check_notes: notes,
      pre_check_completed_at: Time.current,
      additional_findings: findings
    )
    
    # Notify supervisor
    if inspection.supervisor
      Notification.create!(
        user: inspection.supervisor,
        title: "Pre-Check Completed",
        message: "Mechanic #{assigned_mechanic&.name || 'Mechanic'} completed pre-check for job ##{id}. #{findings.count} additional findings.",
        link: "/vmcott/workshop_supervisor/jobs/#{id}/review_findings",
        notification_type: 'info',
        notifiable: self
      )
    end
  end
  
  def has_additional_findings?
    additional_findings.any?
  end
  
  def approve_for_work!
    update!(
      status: :approved_for_work,
      approved_at: Time.current
    )
  end
  
  def reject_additional_findings!(reason)
    update!(
      status: :assigned,
      blocked_reason: reason
    )
  end

  # =====================================================
  # PARTS REQUEST METHODS
  # =====================================================
  
  def request_part!(part_params, mechanic)
    parts_request = parts_requests.create!(
      part_id: part_params[:part_id],
      custom_part_name: part_params[:custom_part_name],
      quantity: part_params[:quantity],
      status: 'pending_approval',  # Changed from 'pending' to 'pending_approval'
      notes: part_params[:notes],
      inspection_job_id: id,
      inspection_id: inspection_id
    )
    
    # Notify supervisor
    if inspection.supervisor
      Notification.create!(
        user: inspection.supervisor,
        title: "Parts Request",
        message: "Mechanic #{mechanic.name} requested #{part_params[:quantity]}x #{part_params[:part_name] || part_params[:custom_part_name]} for job ##{id}",
        link: "/vmcott/workshop_supervisor/parts_requests/#{parts_request.id}",
        notification_type: 'warning',
        notifiable: parts_request
      )
    end
    
    parts_request
  end
  
  def parts_request_pending?
    parts_requests.where(status: 'pending_approval').any?
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
    return false unless status == 'approved_for_work'
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
  
  # =====================================================
  # METHODS FOR WORK ORDER INTEGRATION
  # =====================================================
  
  def update_total_time!
    total = job_tasks.sum(:actual_hours)
    billable = job_tasks.where(status: 'completed').sum(:actual_hours)
    update!(total_time_hours: total, billable_time_hours: billable)
  end
  
  def active_work_session
    job_tasks.includes(:work_sessions).map(&:active_work_session).compact.first
  end
  
  def all_tasks_completed?
    job_tasks.where.not(status: 'completed').empty?
  end
  
  def all_tasks_assigned?
    job_tasks.where(assigned_mechanic_id: nil).empty?
  end
  
  def tasks_in_progress?
    job_tasks.where(status: 'in_progress').any?
  end

  private

  def will_save_change_to_parts?
    inspection_job_parts.any?(&:changed?) || inspection_job_parts.any?(&:new_record?)
  end
end