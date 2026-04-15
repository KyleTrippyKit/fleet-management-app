class InspectionJob < ApplicationRecord
  include Auditable
  
  belongs_to :inspection
  belongs_to :job_template, optional: true
  belongs_to :assigned_mechanic, class_name: 'User', optional: true
  belongs_to :work_order, optional: true
  belongs_to :pre_check_by, class_name: 'User', optional: true
  
  has_many :inspection_job_parts, dependent: :destroy
  has_many :parts, through: :inspection_job_parts
  has_many :mechanic_assignments, dependent: :destroy
  has_many :parts_requests, foreign_key: :inspection_job_id, dependent: :nullify
  has_many :findings, dependent: :destroy
  has_many :job_tasks, dependent: :destroy
  
  # Nested attributes for parts
  accepts_nested_attributes_for :inspection_job_parts, 
                                allow_destroy: true, 
                                reject_if: ->(attrs) { attrs['custom_part_name'].blank? && attrs['part_id'].blank? }
  
  # Job dependencies
  has_many :dependencies_as_job, class_name: 'JobDependency', foreign_key: :job_id, dependent: :destroy
  has_many :dependencies_on, through: :dependencies_as_job, source: :depends_on
  has_many :dependencies_as_dependency, class_name: 'JobDependency', foreign_key: :depends_on_job_id, dependent: :destroy
  has_many :dependent_jobs, through: :dependencies_as_dependency, source: :job

  PRIORITIES = ['low', 'normal', 'high', 'critical'].freeze

  # ✅ SIMPLIFIED STATUS - Only what matters
  # Updated enum to match your methods
  enum :status, {
    draft: 'draft',
    pending_supervisor_review: 'pending_supervisor_review',
    pending_mechanic_review: 'pending_mechanic_review',
    pending_parts_review: 'pending_parts_review',
    approved: 'approved',
    assigned: 'assigned',
    pre_check_in_progress: 'pre_check_in_progress',
    pre_check_completed: 'pre_check_completed',
    pending_approval: 'pending_approval',
    approved_for_work: 'approved_for_work',
    in_progress: 'in_progress',
    paused: 'paused',
    blocked: 'blocked',
    rework_needed: 'rework_needed',
    completed: 'completed',
    qc_pending: 'qc_pending',
    qc_in_progress: 'qc_in_progress',
    qc_passed: 'qc_passed',
    qc_failed: 'qc_failed',
    cancelled: 'cancelled'
  }, default: :draft

  # Existing fields (keep all)
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
  attribute :total_time_hours, :decimal, precision: 5, scale: 2, default: 0
  attribute :billable_time_hours, :decimal, precision: 5, scale: 2, default: 0
  attribute :pre_check_notes, :text
  attribute :pre_check_completed_at, :datetime
  attribute :additional_findings, :jsonb, default: []
  attribute :pre_check_started_at, :datetime
  attribute :qc_submitted_at, :datetime
  attribute :qc_completed_at, :datetime
  attribute :qc_notes, :text
  attribute :qc_inspector_id, :integer
  attribute :qc_failure_reason, :text

  validates :description, presence: true
  validates :priority, inclusion: { in: PRIORITIES }, allow_nil: true

  # ✅ CALLBACK: Prevent modification after approval
  before_update :prevent_modification_after_approval
  before_create :ensure_quotation_not_approved

  # Scopes (simplified)
  scope :pending, -> { where(completed_at: nil) }
  scope :completed, -> { where.not(completed_at: nil) }
  scope :by_priority, -> { order(Arel.sql("CASE priority WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'normal' THEN 2 ELSE 3 END")) }

  # =====================================================
  # ✅ APPROVAL METHODS - SINGLE AUTHORITY
  # =====================================================
  
  # ✅ ONLY Quotation calls this
  def approve_internal!
    return if status_in_database == 'approved'
    update!(status: 'approved')
  end

  # ✅ Guard against modifications after approval
  def prevent_modification_after_approval
    if status_in_database == 'approved'
      errors.add(:base, "Approved jobs cannot be modified")
      throw(:abort)
    end
  end

  # ✅ Prevent jobs from being added after quotation approved
  def ensure_quotation_not_approved
    if inspection.quotations.where(status: 'approved').exists?
      errors.add(:base, "Cannot add jobs after quotation is approved")
      throw(:abort)
    end
  end

  # =====================================================
  # EXISTING METHODS (keep as is)
  # =====================================================

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

  def request_part!(part_params, mechanic)
    parts_request = parts_requests.create!(
      part_id: part_params[:part_id],
      custom_part_name: part_params[:custom_part_name],
      quantity: part_params[:quantity],
      status: 'pending_approval',
      notes: part_params[:notes],
      inspection_job_id: id,
      inspection_id: inspection_id
    )
    
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
    return false unless status == 'approved_for_work'
    return false unless inspection.client_can_start_work?
    return false unless dependencies_satisfied?
    return false if blocked?
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
  
  def can_send_to_qc?
    return false unless completed?
    return false if ['qc_pending', 'qc_in_progress', 'qc_passed'].include?(status)
    return false unless all_tasks_completed?
    return false unless parts_usage_recorded?
    return false if qc_submitted_at.present? && status == 'completed'
    true
  end
  
  def parts_usage_recorded?
    inspection_job_parts.each do |job_part|
      return false unless job_part.quantity_used.present? || job_part.quantity == 0
    end
    true
  end
  
  def submit_to_qc!(inspector_id = nil)
    update!(
      status: :qc_pending,
      qc_submitted_at: Time.current,
      qc_inspector_id: inspector_id
    )
    
    if inspector_id.present?
      Notification.create!(
        user_id: inspector_id,
        title: "QC Submission",
        message: "Job ##{id} has been submitted for QC inspection.",
        link: "/vmcott/qc/jobs/#{id}",
        notification_type: 'info',
        notifiable: self
      )
    end
    
    if inspection.supervisor
      Notification.create!(
        user: inspection.supervisor,
        title: "Job Submitted to QC",
        message: "Job ##{id} has been submitted for QC inspection.",
        link: "/vmcott/workshop_supervisor/jobs/#{id}",
        notification_type: 'info',
        notifiable: self
      )
    end
  end
  
  def start_qc_inspection!(inspector_id)
    update!(
      status: :qc_in_progress,
      qc_inspector_id: inspector_id
    )
  end
  
  def pass_qc!(notes = nil)
    update!(
      status: :qc_passed,
      qc_completed_at: Time.current,
      qc_notes: notes
    )
    
    Notification.create!(
      user: assigned_mechanic,
      title: "QC Passed",
      message: "Job ##{id} has passed QC inspection.",
      link: "/vmcott/mechanic/jobs/#{id}",
      notification_type: 'success',
      notifiable: self
    )
    
    if inspection.supervisor
      Notification.create!(
        user: inspection.supervisor,
        title: "QC Passed",
        message: "Job ##{id} has passed QC inspection.",
        link: "/vmcott/workshop_supervisor/jobs/#{id}",
        notification_type: 'success',
        notifiable: self
      )
    end
  end
  
  def fail_qc!(reason, notes = nil)
    update!(
      status: :qc_failed,
      qc_completed_at: Time.current,
      qc_failure_reason: reason,
      qc_notes: notes
    )
    
    Notification.create!(
      user: assigned_mechanic,
      title: "QC Failed",
      message: "Job ##{id} failed QC: #{reason}",
      link: "/vmcott/mechanic/jobs/#{id}",
      notification_type: 'error',
      notifiable: self
    )
    
    if inspection.supervisor
      Notification.create!(
        user: inspection.supervisor,
        title: "QC Failed",
        message: "Job ##{id} failed QC: #{reason}",
        link: "/vmcott/workshop_supervisor/jobs/#{id}",
        notification_type: 'error',
        notifiable: self
      )
    end
  end
  
  def requeue_for_rework!
    update!(
      status: :rework_needed,
      rework_reason: qc_failure_reason.presence || "Failed QC inspection",
      rework_requested_at: Time.current,
      qc_submitted_at: nil,
      qc_completed_at: nil,
      qc_inspector_id: nil
    )
  end
  
  def qc_completed?
    ['qc_passed', 'qc_failed'].include?(status)
  end
  
  def qc_passed?
    status == 'qc_passed'
  end
  
  def qc_failed?
    status == 'qc_failed'
  end

  def start!
    update!(status: :in_progress, started_at: Time.current)
  end

  def pause!(reason)
    update!(status: :paused, paused_at: Time.current, paused_reason: reason)
  end

  def resume!
    update!(status: :in_progress, paused_at: nil, paused_reason: nil)
  end

  def block!(reason, requires_quote: true)
    update!(status: :blocked, blocked_at: Time.current, blocked_reason: reason)
    
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
    update!(status: :rework_needed, rework_requested_at: Time.current, rework_reason: reason)
  end

  def add_dependency(dependency_job, type: 'required')
    dependencies_as_job.create!(depends_on_job_id: dependency_job.id, dependency_type: type)
  end

  def missing_dependencies
    dependencies_on.where.not(status: 'completed')
  end

  def dependencies_satisfied?
    missing_dependencies.empty?
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
      update!(quantity_used: total_quantity, locked_for_changes: true, locked_at: Time.current)
    end
  end

  def change_log
    if defined?(PaperTrail) && has_paper_trail?
      versions.order(created_at: :desc)
    else
      []
    end
  end
  
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