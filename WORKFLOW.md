# 🧭 FULL WORKFLOW (DETAILED / EXPANDED)

---

## 🟦 1. INTAKE PHASE

WorkOrder created → status: RECEIVED

Customer brings vehicle / submits request

System records:

* Vehicle details
* Customer details
* Reported issues

WorkOrder is opened and queued

---

## 🟩 2. INSPECTION PHASE

Inspector receives WorkOrder

Inspector performs VEHICLE INSPECTION:

* Visual inspection (external damage, leaks)
* Basic functional checks (lights, brakes, engine noise)
* Scan (if diagnostic tools available)

Inspector records:

📋 INSPECTION DATA:

* Observations
* Fault codes (if any)
* Visible issues
* Safety concerns

Inspector creates:
→ RECOMMENDATIONS ONLY

Important:

* Inspector DOES NOT estimate parts or cost
* Inspector ONLY reports observations

---

## 🟨 3. DIAGNOSIS PHASE (MECHANIC)

Mechanic reviews inspector recommendations

Mechanic performs deeper diagnosis:

* Tests components
* Uses tools (scanner, physical checks)

Mechanic records:

📋 FINDINGS:

* Root cause of issues
* Additional hidden issues

Mechanic identifies:

* REQUIRED PARTS (rough estimate)
* Complexity of work

---

## 🟪 4. JOB CREATION PHASE (SUPERVISOR)

Supervisor reviews:

* Inspector recommendations
* Mechanic findings

Supervisor creates JOBS:

Each Job includes:

* Description
* Assigned mechanic
* Estimated labor time
* Linked recommendations + findings
* REQUIRED PARTS (attached)

---

## 🟫 5. PARTS + JOB BUNDLED PHASE

Mechanic reviews assigned jobs

Mechanic requests parts if needed

Supervisor approves or rejects request

Inventory checks stock:

* In Stock → RESERVED
* Not In Stock → PROCUREMENT

Procurement orders from supplier

Parts status:

* AVAILABLE → Continue
* PARTIAL → ON_HOLD
* DELAYED → ON_HOLD

---

## 🟧 6. INITIAL QUOTE PHASE

Supervisor creates INITIAL QUOTE

Includes:

* Labor (per job)
* Parts (linked to jobs)

This is a FULL BUNDLE QUOTE

---

## 🟥 7. CUSTOMER APPROVAL (INITIAL)

Customer reviews quote:

* ACCEPT → Work begins
* PARTIAL → Adjust scope → resend quote
* REJECT → Stop / cancel / revise

---

## 🟩 8. EXECUTION PHASE (MECHANIC)

Mechanic begins assigned jobs

* Follows job instructions
* Uses approved parts
* Logs progress

Tracks:

* Time spent
* Parts used
* Work status

Completes jobs

---

## 🟨 9. ADDITIONAL FINDINGS

Mechanic discovers new issues

Mechanic submits ADDITIONAL FINDINGS

Supervisor decision:

* APPROVE →

  * Create NEW job
  * New parts required
  * New quote required

* REJECT →

  * Continue existing work only

---

## 🟦 10. QC (QUALITY CONTROL)

Inspector verifies:

* Job completion
* Work quality

Results:

* PASS → proceed
* FAIL → rework required

---

## 🟪 11. SUPERVISOR NOTIFICATION

System notifies supervisor:

* Jobs completed
* QC passed

Supervisor informs customer:

* Work completed
* Vehicle ready
* Additional issues (if any)

---

## 🟫 12. ADDITIONAL WORK (OPTIONAL LOOP)

Customer decision:

* APPROVE additional work → new jobs, parts, quote
* DECLINE → continue to billing

---

## 🟧 13. BILLING PHASE

Invoice generated from:

* Approved jobs
* Approved parts
* Labor + markup

Payment:

* PAID → success
* FAILED → retry / hold

---

## 🟩 14. COMPLETION PHASE

WorkOrder marked COMPLETED

System stores:

* Jobs
* Findings
* Parts
* Quotes
* Approvals
* QC results
* Payment records

---

## 🔥 FINAL FLOW SUMMARY

Intake → Inspection → Diagnosis → Jobs → Parts → Quote → Approval → Work → QC → Billing → Completion


send me the full revised model # app/models/inspection_job.rb
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

  # Status workflow - ENHANCED with pre-check, approval stages, and QC
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
    completed: 'completed',
    # QC Statuses
    qc_pending: 'qc_pending',                # NEW: Ready for QC inspection
    qc_in_progress: 'qc_in_progress',        # NEW: Currently in QC
    qc_passed: 'qc_passed',                  # NEW: Passed QC inspection
    qc_failed: 'qc_failed'                   # NEW: Failed QC, needs rework
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
  
  # NEW: QC fields
  attribute :qc_submitted_at, :datetime
  attribute :qc_completed_at, :datetime
  attribute :qc_notes, :text
  attribute :qc_inspector_id, :integer
  attribute :qc_failure_reason, :text

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
  
  # NEW: QC Scopes
  scope :qc_pending, -> { where(status: :qc_pending) }
  scope :in_qc, -> { where(status: :qc_in_progress) }
  scope :qc_passed, -> { where(status: :qc_passed) }
  scope :qc_failed, -> { where(status: :qc_failed) }
  
  # NEW: Scopes for work order integration
  scope :by_work_order, ->(work_order_id) { where(work_order_id: work_order_id) }
  scope :with_active_tasks, -> { joins(:job_tasks).where(job_tasks: { status: ['in_progress', 'pending', 'approved'] }).distinct }
  scope :approved, -> { where(status: ['approved', 'approved_for_work']) }

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
  
  # =====================================================
  # QC METHODS
  # =====================================================
  
  def can_send_to_qc?
    # A job can be sent to QC if:
    # 1. It's completed
    # 2. Not already in QC or QC passed/failed
    # 3. All tasks are completed (if using work order integration)
    # 4. All parts usage is recorded
    # 5. All required documentation is present
    
    return false unless completed?
    return false if ['qc_pending', 'qc_in_progress', 'qc_passed'].include?(status)
    
    # Check if all tasks are completed
    return false unless all_tasks_completed?
    
    # Check if parts usage is properly recorded
    return false unless parts_usage_recorded?
    
    # Check if QC hasn't already been submitted
    return false if qc_submitted_at.present? && status == 'completed'
    
    true
  end
  
  def parts_usage_recorded?
    # Verify that all parts have been recorded as used
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
    
    # Notify QC inspector
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
    
    # Notify supervisor
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
    
    # Notify relevant parties
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
    
    # Notify mechanic about rework needed
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
end send me the part i need to change here too # app/controllers/vmcott/workshop_supervisor/dashboard_controller.rb
class Vmcott::WorkshopSupervisor::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_workshop_supervisor
  before_action :set_stats, only: [:index]

  # CRITICAL: Disable ALL caching for this controller to prevent white screen issues
  before_action :disable_all_caching

  # =====================================================
  # HELPER METHODS (Available in views)
  # =====================================================
  helper_method :calculate_labor_cost, :calculate_parts_cost

  def index
    # ========================================
    # PHASE 4: Jobs needing creation from diagnosis
    # ========================================
    @pending_job_creation = Inspection
      .where(status: 'diagnosed')
      .includes(:vehicle, :findings)
      .order(created_at: :asc)
      .limit(20)

    # ========================================
    # PHASE 5: Parts requests pending approval
    # ========================================
    @pending_parts_requests = PartsRequest
      .where(status: 'requested')
      .includes(:inspection, :part, :inspection_job)
      .order(created_at: :desc)
      .limit(30)

    # ========================================
    # PHASE 6: Quotations pending creation (parts ready)
    # ========================================
    @pending_quotation = Inspection
      .where(status: 'parts_approved')
      .includes(:vehicle, :inspection_jobs, :parts_requests)
      .order(created_at: :asc)
      .limit(20)

    # ========================================
    # PHASE 7: Awaiting customer approval
    # ========================================
    @awaiting_approval = Inspection
      .where(status: 'awaiting_approval')
      .includes(:vehicle, :quotations)
      .order(created_at: :asc)
      .limit(20)

    # ========================================
    # PHASE 8: Active jobs in progress
    # ========================================
    @active_jobs = InspectionJob
      .where(status: 'in_progress')
      .includes(inspection: :vehicle, job_tasks: :work_sessions)
      .order(started_at: :desc)
      .limit(20)

    # ========================================
    # PHASE 9: Additional findings pending review
    # ========================================
    @pending_additional_findings = Inspection
      .where(status: 'additional_findings_pending')
      .includes(:vehicle, :findings)
      .order(updated_at: :desc)
      .limit(20)

    # ========================================
    # PHASE 10: QC pending
    # ========================================
    @qc_pending_inspections = Inspection
      .where(status: 'ready_for_qc')
      .includes(:vehicle, :inspection_jobs)
      .order(updated_at: :desc)
      .limit(20)

    # ========================================
    # PENDING TASKS (Need Approval)
    # ========================================
    @pending_tasks = JobTask
      .where(status: 'pending')
      .includes(inspection_job: { inspection: :vehicle })
      .order(created_at: :asc)
      .limit(50)

    # ========================================
    # BLOCKED TASKS (Need Unblocking)
    # ========================================
    @blocked_tasks = JobTask
      .where(status: 'blocked')
      .includes(inspection_job: { inspection: :vehicle })
      .order(blocked_at: :desc)
      .limit(50)

    # ========================================
    # PENDING WORK ORDERS (Need Approval)
    # ========================================
    @pending_work_orders = WorkOrder
      .where(status: 'awaiting_approval')
      .includes(:vehicle)
      .order(created_at: :asc)
      .limit(20)

    # ========================================
    # PRE-CHECK COMPLETED JOBS (Need Review)
    # ========================================
    @pre_check_completed = InspectionJob
      .where(status: 'pre_check_completed')
      .includes(inspection: :vehicle, assigned_mechanic: {})
      .order(pre_check_completed_at: :desc)
      .limit(30)

    # ========================================
    # PENDING FINDINGS (Need Review)
    # ========================================
    @pending_findings = Finding
      .where(status: 'pending')
      .where(blocking: true)
      .includes(:work_order, :created_by)
      .order(created_at: :desc)
      .limit(20)

    # ========================================
    # WORKFLOW SELECTION PENDING (Backward Compatibility)
    # ========================================
    @workflow_pending = Inspection
      .where(status: 'pending_supervisor_review')
      .where(workflow_selected_by_id: nil)
      .includes(:vehicle, :inspection_jobs, :parts_requests)
      .order(created_at: :asc)
      .limit(20)

    # ========================================
    # STATS
    # ========================================
    @pre_check_count = @pre_check_completed.count
    @pending_parts_count = @pending_parts_requests.count
  end

  # =====================================================
  # 🔥 NEW: RECOMMENDATION METHODS (Phase 3.5)
  # =====================================================

  def recommendations
    @inspection = Inspection.find(params[:inspection_id])
    @recommendations = @inspection.inspection_recommendations.pending_review
    @approved_recommendations = @inspection.inspection_recommendations.approved_but_not_converted
    @mechanics = User.where(role: 'mechanic').active if User.respond_to?(:active)
    @mechanics ||= User.where(role: 'mechanic')
    
    disable_all_caching
  end

  def approve_recommendation
    @recommendation = InspectionRecommendation.find(params[:id])
    
    if @recommendation.approve!(current_user)
      flash[:notice] = "Recommendation approved. You can now convert it to a job."
    else
      flash[:alert] = "Failed to approve recommendation."
    end
    
    redirect_to vmcott_workshop_supervisor_recommendations_path(@recommendation.inspection)
  end

  def reject_recommendation
    @recommendation = InspectionRecommendation.find(params[:id])
    reason = params[:reason] || "Not approved at this time"
    
    if @recommendation.reject!(current_user, reason)
      flash[:notice] = "Recommendation rejected."
    else
      flash[:alert] = "Failed to reject recommendation."
    end
    
    redirect_to vmcott_workshop_supervisor_recommendations_path(@recommendation.inspection)
  end

  def convert_recommendation_to_job
    @recommendation = InspectionRecommendation.find(params[:id])
    
    if @recommendation.can_convert_to_job?
      job = @recommendation.convert_to_job!(current_user)
      
      flash[:notice] = "✅ Job created from recommendation: #{job.description}"
      redirect_to vmcott_workshop_supervisor_job_path(job)
    else
      flash[:alert] = "Cannot convert this recommendation to a job."
      redirect_to vmcott_workshop_supervisor_recommendations_path(@recommendation.inspection)
    end
  end

  # =====================================================
  # WORKFLOW SELECTION METHODS
  # =====================================================

  def select_workflow
    @inspection = Inspection.find(params[:id])

    # Calculate costs
    @labor_cost = calculate_labor_cost(@inspection)
    @parts_cost = calculate_parts_cost(@inspection)
    @total_cost = @labor_cost + @parts_cost

    # Get current rates - safely access agency settings
    agency = current_user.agency

    # Get labor rate from inspection, then agency settings, then default
    @labor_rate = if @inspection.labor_rate.present?
      @inspection.labor_rate
    elsif agency.present?
      labor_setting = agency.agency_settings.find_by(setting_key: 'labor_rate')
      labor_setting&.setting_value&.to_f || 80.0
    else
      80.0
    end

    # Get parts markup from inspection, then agency settings, then default
    @parts_markup = if @inspection.parts_markup_percentage.present?
      @inspection.parts_markup_percentage
    elsif agency.present?
      markup_setting = agency.agency_settings.find_by(setting_key: 'parts_markup')
      markup_setting&.setting_value&.to_i || 30
    else
      30
    end

    # Get all jobs and parts for display
    @jobs = @inspection.inspection_jobs
    @parts_requests = @inspection.parts_requests

    disable_all_caching
  end

  def process_workflow_selection
    @inspection = Inspection.find(params[:id])

    workflow_type = params[:workflow_type]
    labor_rate = params[:labor_rate].to_f
    parts_markup = params[:parts_markup].to_i
    notes = params[:workflow_notes]
    mechanic_id = params[:assigned_mechanic_id]

    # Validate required fields
    unless ['payment_before_work', 'work_before_payment'].include?(workflow_type)
      redirect_to vmcott_workshop_supervisor_select_workflow_path(@inspection),
                  alert: 'Please select a valid workflow type.'
      return
    end

    unless mechanic_id.present?
      flash[:alert] = 'Please assign a mechanic before finalizing.'
      redirect_to vmcott_workshop_supervisor_select_workflow_path(@inspection)
      return
    end

    mechanic = User.find(mechanic_id)

    ActiveRecord::Base.transaction do
      # 1. Update inspection with workflow selection
      @inspection.update!(
        workflow_type: workflow_type,
        workflow_selected_by_id: current_user.id,
        workflow_selected_at: Time.current,
        workflow_notes: notes,
        labor_rate: labor_rate,
        parts_markup_percentage: parts_markup,
        status: 'awaiting_approval'
      )

      # 2. Update job labor costs and create mechanic assignments
      @inspection.inspection_jobs.each do |job|
        new_labor_cost = (job.estimated_hours || 0) * labor_rate

        job.update!(
          estimated_labor_cost: new_labor_cost,
          assigned_mechanic_id: mechanic_id,
          status: 'approved'
        )

        # Create MechanicAssignment record
        MechanicAssignment.find_or_initialize_by(
          inspection_job: job,
          mechanic: mechanic
        ).update!(
          status: 'assigned',
          started_at: Time.current,
          mechanic_notes: "Assigned during workflow selection by #{current_user.name}"
        )
      end

      # 3. Update part costs with markup
      @inspection.parts_requests.each do |request|
        if request.part.present? && request.unit_price.present?
          final_price = request.unit_price * (1 + parts_markup / 100.0)
          request.update!(
            customer_price: final_price,
            status: 'approved'
          )
        end
      end

      # 4. Create notification for procurement team
      procurement_users = User.where(role: 'procurement').or(User.where(role: 'billing'))
      total_cost = @inspection.inspection_jobs.sum(:estimated_labor_cost) + @inspection.parts_requests.sum(:customer_price)

      procurement_users.each do |procurement_user|
        Notification.create!(
          user: procurement_user,
          title: "Job Ready for Quotation",
          message: "Workflow '#{workflow_type.humanize}' selected for #{@inspection.vehicle.license_plate}. Total: $#{'%.2f' % total_cost}",
          link: vmcott_procurement_quotation_workspace_path(inspection_id: @inspection.id),
          notification_type: 'info',
          notifiable: @inspection
        )
      end

      # 5. Notify mechanic
      Notification.create!(
        user: mechanic,
        title: "New Job Assignment",
        message: "You have been assigned to #{@inspection.inspection_jobs.count} job(s) for vehicle #{@inspection.vehicle.license_plate}",
        link: vmcott_mechanic_dashboard_path,
        notification_type: 'info',
        notifiable: @inspection
      )

      flash[:notice] = "✅ Workflow selected. #{@inspection.inspection_jobs.count} job(s) assigned to #{mechanic.name}. Ready for quotation."
    end

    redirect_to vmcott_workshop_supervisor_dashboard_path
  rescue => e
    Rails.logger.error "Error in workflow selection: #{e.message}"
    flash[:alert] = "Error: #{e.message}"
    redirect_to vmcott_workshop_supervisor_select_workflow_path(@inspection)
  end

  def review_workflow
    @inspection = Inspection.find(params[:id])
    @workflow_selected = @inspection.workflow_selected_by_id.present?
    @jobs = @inspection.inspection_jobs
    @parts_requests = @inspection.parts_requests
    @labor_cost = calculate_labor_cost(@inspection)
    @parts_cost = calculate_parts_cost(@inspection)
    @total_cost = @labor_cost + @parts_cost

    disable_all_caching
  end

  def review_workflow_selection
    review_workflow
  end

  def workflow_pending
    @workflow_pending = Inspection
      .where(status: 'pending_supervisor_review')
      .where(workflow_selected_by_id: nil)
      .includes(:vehicle, :inspection_jobs, :parts_requests)
      .order(created_at: :asc)
      .page(params[:page])
      .per(20)

    disable_all_caching
  end

  def workflow_selections
    @workflow_selections = Inspection
      .where.not(workflow_selected_by_id: nil)
      .includes(:vehicle, :inspection_jobs, :parts_requests, :workflow_selected_by)
      .order(workflow_selected_at: :desc)
      .page(params[:page])
      .per(20)

    @workflow_type_filter = params[:workflow_type]
    @workflow_selections = @workflow_selections.where(workflow_type: @workflow_type_filter) if @workflow_type_filter.present?

    disable_all_caching
  end

  # =====================================================
  # PRE-CHECK REVIEW METHODS
  # =====================================================

  def review_pre_check
    @job = InspectionJob.find(params[:id])
    @additional_findings = @job.additional_findings
    @mechanic = @job.assigned_mechanic

    disable_all_caching
  end

  def approve_pre_check
    @job = InspectionJob.find(params[:id])

    ActiveRecord::Base.transaction do
      @job.update!(
        status: 'approved_for_work',
        approved_at: Time.current,
        supervisor_id: current_user.id
      )

      # Update mechanic assignment
      assignment = MechanicAssignment.find_by(inspection_job: @job)
      if assignment
        assignment.update!(
          mechanic_notes: "#{assignment.mechanic_notes}\n\nPre-check approved by #{current_user.name} at #{Time.current}"
        )
      end

      if params[:approved_findings].present?
        params[:approved_findings].each do |finding_index, finding_data|
          if finding_data[:approved] == 'true'
            additional_job = @job.inspection.inspection_jobs.create!(
              description: finding_data[:description],
              priority: finding_data[:severity] == 'critical' ? 'high' : 'normal',
              estimated_hours: finding_data[:estimated_hours],
              status: 'approved_for_work',
              recommendation_source: 'mechanic_pre_check',
              parent_job_id: @job.id,
              assigned_mechanic_id: @job.assigned_mechanic_id
            )

            # Create mechanic assignment for additional job
            if @job.assigned_mechanic
              MechanicAssignment.create!(
                inspection_job: additional_job,
                mechanic: @job.assigned_mechanic,
                status: 'assigned',
                mechanic_notes: "Additional work from pre-check findings"
              )
            end

            Notification.create!(
              user: @job.assigned_mechanic,
              title: "Additional Work Approved",
              message: "Additional job '#{finding_data[:description]}' has been approved for work.",
              link: "/vmcott/mechanic/jobs/#{additional_job.id}",
              notification_type: 'success',
              notifiable: additional_job
            )
          end
        end
      end

      Notification.create!(
        user: @job.assigned_mechanic,
        title: "Pre-Check Approved",
        message: "Your pre-check for job ##{@job.id} has been approved. You can now start work.",
        link: "/vmcott/mechanic/jobs/#{@job.id}",
        notification_type: 'success',
        notifiable: @job
      )

      flash[:notice] = "✅ Pre-check approved. Job is ready for work."
    end

    redirect_to vmcott_workshop_supervisor_dashboard_path
  rescue => e
    Rails.logger.error "Error approving pre-check: #{e.message}"
    flash[:alert] = "Error approving pre-check: #{e.message}"
    redirect_to vmcott_workshop_supervisor_review_pre_check_path(@job)
  end

  def reject_pre_check
    @job = InspectionJob.find(params[:id])
    reason = params[:rejection_reason] || "Additional work not approved at this time"

    ActiveRecord::Base.transaction do
      @job.update!(
        status: 'assigned',
        blocked_reason: reason
      )

      # Update mechanic assignment
      assignment = MechanicAssignment.find_by(inspection_job: @job)
      if assignment
        assignment.update!(
          mechanic_notes: "#{assignment.mechanic_notes}\n\nPre-check REJECTED by #{current_user.name}: #{reason}"
        )
      end

      Notification.create!(
        user: @job.assigned_mechanic,
        title: "Pre-Check Findings Rejected",
        message: "Your pre-check findings for job ##{@job.id} were not approved. Reason: #{reason}",
        link: "/vmcott/mechanic/jobs/#{@job.id}",
        notification_type: 'warning',
        notifiable: @job
      )

      flash[:alert] = "❌ Pre-check findings rejected. Job returned to mechanic."
    end

    redirect_to vmcott_workshop_supervisor_dashboard_path
  end

  # =====================================================
  # PARTS REQUEST APPROVAL METHODS (UPDATED)
  # =====================================================

  def review_parts_request
    @parts_request = PartsRequest.find(params[:id])
    @job = @parts_request.inspection_job
    @vehicle = @parts_request.inspection&.vehicle

    disable_all_caching
  end

  def approve_parts_request
    @parts_request = PartsRequest.find(params[:id])
    
    if @parts_request.update(
      status: 'approved', 
      approved_at: Time.current, 
      approved_by_id: current_user.id
    )
      # Notify Inventory Managers
      inventory_managers = User.where(role: 'inventory_manager').or(User.where(role: 'parts_coordinator'))
      
      inventory_managers.each do |im|
        Notification.create!(
          user: im,
          title: "Parts Request Approved",
          message: "Parts request ##{@parts_request.id} for #{@parts_request.quantity}x #{@parts_request.part&.name || @parts_request.custom_part_name || 'Custom part'} has been approved by #{current_user.name}. Please process.",
          link: vmcott_inventory_manager_dashboard_path,
          notification_type: 'info',
          notifiable: @parts_request
        )
      end
      
      # Notify the mechanic who requested the part
      if @parts_request.requested_by.present?
        Notification.create!(
          user: @parts_request.requested_by,
          title: "Parts Request Approved",
          message: "Your parts request for #{@parts_request.quantity}x #{@parts_request.part&.name || @parts_request.custom_part_name || 'Custom part'} has been approved and sent to inventory manager.",
          link: vmcott_mechanic_dashboard_path,
          notification_type: 'success',
          notifiable: @parts_request
        )
      end
      
      # Notify the mechanic assigned to the job (if different from requester)
      if @parts_request.inspection_job&.assigned_mechanic.present? && @parts_request.inspection_job.assigned_mechanic != @parts_request.requested_by
        Notification.create!(
          user: @parts_request.inspection_job.assigned_mechanic,
          title: "Parts Request Approved",
          message: "Parts request for #{@parts_request.quantity}x #{@parts_request.part&.name || @parts_request.custom_part_name || 'Custom part'} has been approved and sent to inventory manager.",
          link: vmcott_mechanic_job_path(@parts_request.inspection_job),
          notification_type: 'success',
          notifiable: @parts_request
        )
      end
      
      flash[:notice] = "✅ Parts request approved. Inventory manager will process it."
      
      # Redirect back to the job page if coming from there
      if @parts_request.inspection_job.present?
        redirect_to vmcott_workshop_supervisor_job_path(@parts_request.inspection_job)
      else
        redirect_to vmcott_workshop_supervisor_dashboard_path
      end
    else
      flash[:alert] = "Error approving parts request: #{@parts_request.errors.full_messages.join(', ')}"
      redirect_back(fallback_location: vmcott_workshop_supervisor_dashboard_path)
    end
  rescue => e
    Rails.logger.error "Error approving parts request: #{e.message}"
    flash[:alert] = "Error approving parts request: #{e.message}"
    redirect_back(fallback_location: vmcott_workshop_supervisor_dashboard_path)
  end

  def reject_parts_request
    @parts_request = PartsRequest.find(params[:id])
    reason = params[:reason] || params[:rejection_reason] || "Not approved at this time"
    
    if @parts_request.update(
      status: 'rejected', 
      rejected_at: Time.current, 
      rejected_by_id: current_user.id,
      rejection_reason: reason
    )
      # Notify the mechanic who requested the part
      if @parts_request.requested_by.present?
        Notification.create!(
          user: @parts_request.requested_by,
          title: "Parts Request Rejected",
          message: "Your parts request for #{@parts_request.quantity}x #{@parts_request.part&.name || @parts_request.custom_part_name || 'Custom part'} was rejected. Reason: #{reason}",
          link: vmcott_mechanic_dashboard_path,
          notification_type: 'error',
          notifiable: @parts_request
        )
      end
      
      # Notify the mechanic assigned to the job (if different from requester)
      if @parts_request.inspection_job&.assigned_mechanic.present? && @parts_request.inspection_job.assigned_mechanic != @parts_request.requested_by
        Notification.create!(
          user: @parts_request.inspection_job.assigned_mechanic,
          title: "Parts Request Rejected",
          message: "Parts request for #{@parts_request.quantity}x #{@parts_request.part&.name || @parts_request.custom_part_name || 'Custom part'} was rejected. Reason: #{reason}",
          link: vmcott_mechanic_job_path(@parts_request.inspection_job),
          notification_type: 'error',
          notifiable: @parts_request
        )
      end
      
      flash[:alert] = "❌ Parts request rejected: #{reason}"
      
      # Redirect back to the job page if coming from there
      if @parts_request.inspection_job.present?
        redirect_to vmcott_workshop_supervisor_job_path(@parts_request.inspection_job)
      else
        redirect_to vmcott_workshop_supervisor_dashboard_path
      end
    else
      flash[:alert] = "Error rejecting parts request: #{@parts_request.errors.full_messages.join(', ')}"
      redirect_back(fallback_location: vmcott_workshop_supervisor_dashboard_path)
    end
  rescue => e
    Rails.logger.error "Error rejecting parts request: #{e.message}"
    flash[:alert] = "Error rejecting parts request: #{e.message}"
    redirect_back(fallback_location: vmcott_workshop_supervisor_dashboard_path)
  end

  # =====================================================
  # 🔥 UPDATED: PHASE 4 - JOB CREATION (FIXED for missing columns)
  # =====================================================

  def job_creation
      @inspection = Inspection.find(params[:id])
      
      # Load INSPECTOR recommendations
      @inspector_recommendations = @inspection.inspection_recommendations.where(status: 'pending')
      
      # Load MECHANIC findings - THIS IS THE FIX
      @mechanic_findings = @inspection.findings.where(finding_type: 'mechanic')
      
      # For backward compatibility
      @findings = @mechanic_findings
      
      @mechanics = User.where(role: 'mechanic').order(:name)
      @job_templates = JobTemplate.active if defined?(JobTemplate)

      disable_all_caching
    end

    def create_jobs
    @inspection = Inspection.find(params[:id])

    ActiveRecord::Base.transaction do
      created_jobs = []
      
      # Process inspector recommendations
      if params[:inspector_recommendations].present?
        params[:inspector_recommendations].each do |rec_id, rec_data|
          next unless rec_data[:include] == 'true'
          
          recommendation = InspectionRecommendation.find(rec_id)
          job = @inspection.inspection_jobs.create!(
            description: rec_data[:description] || recommendation.description,
            estimated_hours: rec_data[:estimated_hours] || recommendation.estimated_hours || 1,
            status: 'pending_approval',
            recommendation_source: 'inspector',
            priority: rec_data[:priority] || recommendation.priority || 'normal'
          )
          created_jobs << job
        end
      end
      
      # Process mechanic findings
      if params[:mechanic_findings].present?
        params[:mechanic_findings].each do |finding_id, finding_data|
          next unless finding_data[:include] == 'true'
          
          finding = Finding.find(finding_id)
          job = @inspection.inspection_jobs.create!(
            description: finding_data[:description] || finding.description,
            estimated_hours: finding_data[:estimated_hours] || 1,
            status: 'pending_customer_approval',
            recommendation_source: 'mechanic',
            priority: finding_data[:priority] || 'normal'
          )
          created_jobs << job
        end
      end
      
      # Process custom jobs
      if params[:jobs].present?
        params[:jobs].each do |job_data|
          next if job_data[:description].blank?
          
          job = @inspection.inspection_jobs.create!(
            description: job_data[:description],
            estimated_hours: job_data[:estimated_hours] || 1,
            status: 'pending_approval',
            priority: job_data[:priority] || 'normal',
            recommendation_source: 'supervisor'
          )
          created_jobs << job
          
          if job_data[:mechanic_id].present?
            job.update!(assigned_mechanic_id: job_data[:mechanic_id])
          elsif params[:default_mechanic_id].present?
            job.update!(assigned_mechanic_id: params[:default_mechanic_id])
          end
        end
      end
      
      if created_jobs.any?
        @inspection.update!(status: 'jobs_created')
        flash[:notice] = "✅ Successfully created #{created_jobs.count} job(s)"
      else
        flash[:alert] = "No jobs were created."
        redirect_to vmcott_workshop_supervisor_job_creation_path(@inspection) and return
      end
    end
    
    redirect_to vmcott_workshop_supervisor_dashboard_path
  rescue => e
    flash[:alert] = "Error creating jobs: #{e.message}"
    redirect_to vmcott_workshop_supervisor_job_creation_path(@inspection)
  end

  # =====================================================
  # PHASE 5: PARTS APPROVAL
  # =====================================================

  def parts_approval
    @inspection = Inspection.find(params[:id])
    @parts_requests = @inspection.parts_requests.where(status: 'pending_approval')

    disable_all_caching
  end

  def approve_parts
    @inspection = Inspection.find(params[:id])

    ActiveRecord::Base.transaction do
      @inspection.parts_requests.where(status: 'pending_approval').each do |request|
        request.update!(status: 'approved', approved_at: Time.current, approved_by_id: current_user.id)

        # Check inventory
        if request.part.present? && request.part.current_stock.to_i >= request.quantity.to_i
          request.update!(in_stock: true)
        else
          request.update!(in_stock: false)
          notify_procurement_for_parts(request)
        end
      end

      @inspection.approve_parts! if @inspection.respond_to?(:approve_parts!)

      flash[:notice] = "✅ Parts approved. Ready for quotation."
    end

    redirect_to vmcott_workshop_supervisor_quotation_creation_path(@inspection)
  end

  # =====================================================
  # PHASE 6: QUOTATION CREATION
  # =====================================================

  def quotation_creation
    @inspection = Inspection.find(params[:id])
    @jobs = @inspection.inspection_jobs
    @parts_requests = @inspection.parts_requests.where(status: 'approved')
    @labor_rate = @inspection.labor_rate || 80.0
    @parts_markup = @inspection.parts_markup_percentage || 30

    disable_all_caching
  end

  def create_quotation
    @inspection = Inspection.find(params[:id])
    labor_rate = params[:labor_rate].to_f
    parts_markup = params[:parts_markup].to_i
    workflow_type = params[:workflow_type]
    mechanic_id = params[:assigned_mechanic_id]

    ActiveRecord::Base.transaction do
      # Update inspection with pricing and workflow
      @inspection.update!(
        labor_rate: labor_rate,
        parts_markup_percentage: parts_markup,
        workflow_type: workflow_type,
        assigned_mechanic_id: mechanic_id,
        workflow_selected_by_id: current_user.id,
        workflow_selected_at: Time.current,
        workflow_notes: params[:workflow_notes]
      )

      # Update job costs
      @inspection.inspection_jobs.each do |job|
        new_labor_cost = (job.estimated_hours || 0) * labor_rate
        job.update!(
          estimated_labor_cost: new_labor_cost,
          status: 'approved'
        )
      end

      # Update part costs
      @inspection.parts_requests.where(status: 'approved').each do |request|
        if request.unit_price.present?
          final_price = request.unit_price * (1 + parts_markup / 100.0)
          request.update!(customer_price: final_price)
        end
      end

      # Create quotation
      @inspection.create_quotation! if @inspection.respond_to?(:create_quotation!)
      @inspection.send_quotation_to_client! if @inspection.respond_to?(:send_quotation_to_client!)
      
      # Update status
      @inspection.update!(status: 'awaiting_approval')

      flash[:notice] = "✅ Quotation created and sent to client for approval."
    end

    redirect_to vmcott_workshop_supervisor_dashboard_path
  rescue => e
    Rails.logger.error "Error creating quotation: #{e.message}"
    flash[:alert] = "Error creating quotation: #{e.message}"
    redirect_to vmcott_workshop_supervisor_quotation_creation_path(@inspection)
  end

  # =====================================================
  # PHASE 9: ADDITIONAL FINDINGS REVIEW
  # =====================================================

  def additional_findings
    @inspection = Inspection.find(params[:id])
    @pending_findings = @inspection.findings.where(status: 'pending')

    disable_all_caching
  end

  def approve_additional_finding
    @inspection = Inspection.find(params[:id])
    finding = @inspection.findings.find(params[:finding_id])

    if params[:approve] == 'true'
      new_job = @inspection.inspection_jobs.create!(
        description: finding.description,
        priority: finding.severity == 'critical' ? 'high' : 'normal',
        estimated_hours: params[:estimated_hours] || 2.0,
        status: 'pending_quotation'
      )

      @inspection.update!(has_additional_findings: false, status: :in_progress)
      finding.update!(status: 'approved')

      flash[:notice] = "✅ Additional work approved and added to quotation."
    else
      finding.update!(status: 'rejected', notes: params[:rejection_reason])
      @inspection.update!(has_additional_findings: false, status: :in_progress)
      flash[:alert] = "❌ Additional work rejected."
    end

    redirect_to vmcott_workshop_supervisor_inspection_path(@inspection)
  end

  # =====================================================
  # INSPECTION STATUS MANAGEMENT METHODS
  # =====================================================

  def inspection_show
    @inspection = Inspection.find(params[:id])
    @jobs = @inspection.inspection_jobs
    @parts_requests = @inspection.parts_requests
    @findings = @inspection.findings
    @mechanics = User.where(role: 'mechanic')
    @timeline = timeline_events(@inspection)
    @quotation = @inspection.latest_quotation

    disable_all_caching
  end

  def update_inspection_status
    @inspection = Inspection.find(params[:id])
    new_status = params[:status]

    if @inspection.can_transition_to?(new_status)
      @inspection.transition_to!(new_status, params[:reason])
      flash[:notice] = "Inspection status updated to #{new_status.humanize}"
    else
      flash[:alert] = "Cannot transition from #{@inspection.status} to #{new_status}"
    end

    redirect_back(fallback_location: vmcott_workshop_supervisor_dashboard_path)
  end

  def approve_rework
    @inspection = Inspection.find(params[:id])

    if @inspection.rework_required
      @inspection.update!(
        rework_required: false,
        rework_reason: nil,
        qc_failed_at: nil
      )

      Notification.create!(
        user_id: @inspection.assigned_mechanic_id,
        title: "Rework Approved",
        message: "Your rework for inspection ##{@inspection.id} has been approved.",
        link: "/vmcott/mechanic/inspections/#{@inspection.id}",
        notification_type: 'success',
        notifiable: @inspection
      )

      flash[:notice] = "Rework approved. Inspection can proceed to QC."
    else
      flash[:alert] = "No rework required for this inspection."
    end

    redirect_to vmcott_workshop_supervisor_inspection_path(@inspection)
  end

  def inspection_qc
    @inspection = Inspection.find(params[:id])
    @jobs = @inspection.inspection_jobs

    disable_all_caching
  end

  def inspection_pass_qc
    @inspection = Inspection.find(params[:id])
    inspector = current_user

    if @inspection.status == 'in_progress'
      @inspection.pass_qc!(inspector.id, params[:qc_notes])
      flash[:notice] = "QC passed. Inspection is ready for pickup."
    else
      flash[:alert] = "Inspection cannot be marked as QC passed in its current state."
    end

    redirect_to vmcott_workshop_supervisor_inspection_path(@inspection)
  end

  def inspection_fail_qc
    @inspection = Inspection.find(params[:id])
    inspector = current_user
    reason = params[:reason] || "QC failed"

    if @inspection.status == 'in_progress'
      @inspection.fail_qc!(reason, inspector.id)
      flash[:alert] = "QC failed. Rework required."
    else
      flash[:alert] = "Inspection cannot be marked as QC failed in its current state."
    end

    redirect_to vmcott_workshop_supervisor_inspection_path(@inspection)
  end

  # =====================================================
  # TASKS METHODS
  # =====================================================

  def tasks
    @tasks = JobTask
      .includes(inspection_job: { inspection: :vehicle })
      .order(created_at: :desc)
      .page(params[:page])
      .per(20)

    @status_filter = params[:status]
    @tasks = @tasks.where(status: @status_filter) if @status_filter.present?

    disable_all_caching
  end

  def task_show
    @task = JobTask.find(params[:id])
    @work_sessions = @task.work_sessions.order(started_at: :desc)
    @dependencies = @task.depends_on

    @inspection_job = @task.inspection_job
    @work_order = @inspection_job&.work_order if @inspection_job.present?
    @mechanic = @task.assigned_mechanic

    unless @inspection_job
      Rails.logger.warn "Task #{@task.id} has no inspection_job associated"
    end

    unless @work_order
      Rails.logger.warn "Task #{@task.id} has no work_order (inspection_job_id: #{@inspection_job&.id})"
    end

    disable_all_caching
  end

  def task_approve
    @task = JobTask.find(params[:id])

    if @task.status == 'pending'
      @task.transition_to!('approved', current_user, request.remote_ip)

      if @task.assigned_mechanic
        Notification.create!(
          user: @task.assigned_mechanic,
          title: "Task Approved",
          message: "Task '#{@task.name}' has been approved. You can start working.",
          link: "/vmcott/mechanic/tasks/#{@task.id}",
          notification_type: 'success',
          notifiable: @task
        )
      end

      flash[:notice] = "Task approved successfully."
    else
      flash[:alert] = "Task cannot be approved in its current state."
    end

    redirect_to vmcott_workshop_supervisor_task_path(@task)
  end

  def task_reject
    @task = JobTask.find(params[:id])
    reason = params[:reason] || "Task rejected by supervisor"

    if @task.status == 'pending'
      @task.transition_to!('skipped', current_user, request.remote_ip)
      @task.update!(blocked_reason: reason)

      Notification.create!(
        user: @task.inspection_job.created_by,
        title: "Task Rejected",
        message: "Task '#{@task.name}' was rejected. Reason: #{reason}",
        link: "/vmcott/workshop_supervisor/tasks/#{@task.id}",
        notification_type: 'error',
        notifiable: @task
      )

      flash[:notice] = "Task rejected."
    else
      flash[:alert] = "Task cannot be rejected."
    end

    redirect_to vmcott_workshop_supervisor_task_path(@task)
  end

  def task_unblock
    @task = JobTask.find(params[:id])

    if @task.status == 'blocked'
      service = TaskExecutionService.new(@task, current_user)
      idempotency_key = "unblock_#{@task.id}_#{Time.current.to_i}"

      if service.unblock(idempotency_key)
        flash[:notice] = "Task unblocked successfully."
      else
        flash[:alert] = service.errors.join(", ")
      end
    else
      flash[:alert] = "Task is not blocked."
    end

    redirect_to vmcott_workshop_supervisor_task_path(@task)
  end

  def task_assign_mechanic
    @task = JobTask.find(params[:id])
    mechanic_id = params[:mechanic_id]

    if @task.status == 'approved' && mechanic_id.present?
      mechanic = User.find(mechanic_id)

      @task.update!(
        assigned_mechanic: mechanic,
        assigned_at: Time.current
      )

      # Create or update mechanic assignment
      if @task.inspection_job.present?
        MechanicAssignment.find_or_initialize_by(
          inspection_job: @task.inspection_job,
          mechanic: mechanic
        ).update!(
          status: 'assigned',
          mechanic_notes: "Assigned via task #{@task.name}"
        )
      end

      Notification.create!(
        user: mechanic,
        title: "Task Assigned",
        message: "Task '#{@task.name}' has been assigned to you.",
        link: "/vmcott/mechanic/tasks/#{@task.id}",
        notification_type: 'info',
        notifiable: @task
      )

      flash[:notice] = "Task assigned to #{mechanic.name}."
    else
      flash[:alert] = "Could not assign task."
    end

    redirect_to vmcott_workshop_supervisor_task_path(@task)
  end

  # =====================================================
  # WORK ORDERS METHODS
  # =====================================================

  def work_orders
    @work_orders = WorkOrder
      .includes(:vehicle, :customer)
      .order(created_at: :desc)
      .page(params[:page])
      .per(20)

    @status_filter = params[:status]
    @work_orders = @work_orders.where(status: @status_filter) if @status_filter.present?

    disable_all_caching
  end

  def work_order_show
    @work_order = WorkOrder.find(params[:id])
    @inspections = @work_order.inspections
    @jobs = @work_order.inspection_jobs
    @tasks = @work_order.job_tasks
    @findings = @work_order.findings
    @timeline = @work_order.timeline_events

    disable_all_caching
  end

  def work_order_approve
    @work_order = WorkOrder.find(params[:id])
    service = WorkOrderService.new(@work_order, current_user)

    if service.transition_to('approved')
      flash[:notice] = "Work order approved."
    else
      flash[:alert] = service.errors.join(", ")
    end

    redirect_to vmcott_workshop_supervisor_work_order_path(@work_order)
  end

  def work_order_hold
    @work_order = WorkOrder.find(params[:id])
    service = WorkOrderService.new(@work_order, current_user)
    reason = params[:reason] || "Placed on hold by supervisor"

    if service.transition_to('on_hold')
      @work_order.update!(hold_reason: reason)
      flash[:notice] = "Work order placed on hold."
    else
      flash[:alert] = service.errors.join(", ")
    end

    redirect_to vmcott_workshop_supervisor_work_order_path(@work_order)
  end

  # =====================================================
  # FINDINGS METHODS
  # =====================================================

  def findings
    @findings = Finding
      .includes(:work_order, :created_by)
      .order(created_at: :desc)
      .page(params[:page])
      .per(20)

    @status_filter = params[:status]
    @findings = @findings.where(status: @status_filter) if @status_filter.present?

    disable_all_caching
  end

  def finding_show
    @finding = Finding.find(params[:id])
    @work_order = @finding.work_order
    @tasks = @work_order&.job_tasks || []

    disable_all_caching
  end

  def finding_approve
    @finding = Finding.find(params[:id])

    if @finding.status == 'pending'
      @finding.update!(
        status: 'approved',
        approved_by: current_user,
        approved_at: Time.current
      )

      if params[:create_task] == 'true'
        task = @finding.work_order.job_tasks.create!(
          inspection_job: @finding.inspection_job,
          name: @finding.description,
          description: @finding.description,
          status: 'approved',
          estimated_hours: params[:estimated_hours],
          priority: @finding.severity == 'critical' ? 'high' : 'normal'
        )

        flash[:notice] = "Finding approved and task created."
      else
        flash[:notice] = "Finding approved."
      end

      Notification.create!(
        user: @finding.created_by,
        title: "Finding Approved",
        message: "Your finding has been approved.",
        link: "/vmcott/workshop_supervisor/findings/#{@finding.id}",
        notification_type: 'success',
        notifiable: @finding
      )
    else
      flash[:alert] = "Finding cannot be approved."
    end

    redirect_to vmcott_workshop_supervisor_finding_path(@finding)
  end

  def finding_reject
    @finding = Finding.find(params[:id])
    reason = params[:reason] || "Finding rejected"

    if @finding.status == 'pending'
      @finding.update!(
        status: 'rejected',
        approved_by: current_user,
        approved_at: Time.current,
        notes: reason
      )

      flash[:notice] = "Finding rejected."
    else
      flash[:alert] = "Finding cannot be rejected."
    end

    redirect_to vmcott_workshop_supervisor_finding_path(@finding)
  end

  # =====================================================
  # MECHANICS & REPORTS METHODS
  # =====================================================

  def mechanics
    @mechanics = if User.respond_to?(:active)
      User.where(role: 'mechanic').active
    else
      User.where(role: 'mechanic')
    end

    @task_counts = JobTask.group(:assigned_mechanic_id).count
    @pre_check_counts = InspectionJob.where(status: 'pre_check_completed').group(:assigned_mechanic_id).count
    @completed_today = JobTask.where(status: 'completed')
                              .where('completed_at >= ?', Time.current.beginning_of_day)
                              .group(:assigned_mechanic_id)
                              .count

    # Get mechanic assignment stats
    @active_assignments = MechanicAssignment.where(status: 'in_progress').group(:mechanic_id).count
    @completed_assignments = MechanicAssignment.where(status: 'completed').where('completed_at >= ?', Time.current.beginning_of_day).group(:mechanic_id).count

    disable_all_caching
  end

  def reports
    @start_date = if params[:start_date].present?
      begin
        Date.parse(params[:start_date])
      rescue
        1.week.ago.to_date
      end
    else
      1.week.ago.to_date
    end

    @end_date = if params[:end_date].present?
      begin
        Date.parse(params[:end_date])
      rescue
        Date.current
      end
    else
      Date.current
    end

    @tasks_completed = JobTask.where(status: 'completed')
                              .where(completed_at: @start_date.beginning_of_day..@end_date.end_of_day)
                              .count

    @total_hours = WorkSession.where(session_type: 'work')
                              .where(started_at: @start_date.beginning_of_day..@end_date.end_of_day)
                              .sum(:duration_hours)

    @tasks_by_mechanic = JobTask.where(status: 'completed')
                                .where(completed_at: @start_date.beginning_of_day..@end_date.end_of_day)
                                .group(:assigned_mechanic_id)
                                .count

    @hours_by_mechanic = WorkSession.where(session_type: 'work')
                                    .where(started_at: @start_date.beginning_of_day..@end_date.end_of_day)
                                    .group(:mechanic_id)
                                    .sum(:duration_hours)

    @work_orders_completed = WorkOrder.where(status: 'completed')
                                      .where(completed_at: @start_date.beginning_of_day..@end_date.end_of_day)
                                      .count

    @total_revenue = WorkOrder.where(status: 'completed')
                              .where(completed_at: @start_date.beginning_of_day..@end_date.end_of_day)
                              .sum(:total_amount)

    @parts_requests_approved = PartsRequest.where(status: 'approved')
                                           .where(approved_at: @start_date.beginning_of_day..@end_date.end_of_day)
                                           .count

    @pre_check_completed = InspectionJob.where(status: 'pre_check_completed')
                                        .where(pre_check_completed_at: @start_date.beginning_of_day..@end_date.end_of_day)
                                        .count

    @workflow_payment_before = Inspection.where(workflow_type: 'payment_before_work')
                                         .where(workflow_selected_at: @start_date.beginning_of_day..@end_date.end_of_day)
                                         .count

    @workflow_work_before = Inspection.where(workflow_type: 'work_before_payment')
                                      .where(workflow_selected_at: @start_date.beginning_of_day..@end_date.end_of_day)
                                      .count

    # Mechanic assignment stats
    @assignments_created = MechanicAssignment.where(created_at: @start_date.beginning_of_day..@end_date.end_of_day).count
    @assignments_completed = MechanicAssignment.where(status: 'completed').where(completed_at: @start_date.beginning_of_day..@end_date.end_of_day).count
    @qc_pending_count = MechanicAssignment.where.not(qc_requested_at: nil).where(qc_completed_at: nil).count

    disable_all_caching
  end

  # =====================================================
  # JOB MANAGEMENT METHODS
  # =====================================================

  def jobs
    @jobs = InspectionJob
      .includes(inspection: :vehicle, assigned_mechanic: {})
      .order(created_at: :desc)
      .page(params[:page])
      .per(20)

    @status_filter = params[:status]
    @jobs = @jobs.where(status: @status_filter) if @status_filter.present?

    disable_all_caching
  end

  def job_show
    @job = InspectionJob.find(params[:id])
    @inspection = @job.inspection
    @vehicle = @inspection&.vehicle
    @mechanic = @job.assigned_mechanic
    @parts_requests = @job.parts_requests
    @tasks = @job.job_tasks
    @work_sessions = @job.job_tasks.flat_map(&:work_sessions)
    @findings = @job.inspection.findings.where(inspection_job_id: @job.id) if @job.inspection.present?

    disable_all_caching
  end

  def approve_job
    @job = InspectionJob.find(params[:id])

    if @job.status == 'pending_approval'
      @job.update!(
        status: 'approved',
        approved_at: Time.current,
        approved_by: current_user
      )

      Notification.create!(
        user: @job.inspection.created_by,
        title: "Job Approved",
        message: "Job ##{@job.id} has been approved",
        link: vmcott_workshop_supervisor_job_path(@job),
        notification_type: 'success',
        notifiable: @job
      )

      flash[:notice] = "Job approved successfully."
    else
      flash[:alert] = "Job cannot be approved in its current state."
    end

    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def reject_job
    @job = InspectionJob.find(params[:id])
    reason = params[:rejection_reason] || "No reason provided"

    if @job.status == 'pending_approval'
      @job.update!(
        status: 'rejected',
        rejected_at: Time.current,
        rejected_by: current_user,
        rejection_reason: reason
      )

      Notification.create!(
        user: @job.inspection.created_by,
        title: "Job Rejected",
        message: "Job ##{@job.id} was rejected. Reason: #{reason}",
        link: vmcott_workshop_supervisor_job_path(@job),
        notification_type: 'error',
        notifiable: @job
      )

      flash[:notice] = "Job rejected."
    else
      flash[:alert] = "Job cannot be rejected."
    end

    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def assign_job
    @job = InspectionJob.find(params[:id])
    mechanic_id = params[:mechanic_id]

    if @job.status == 'approved' && mechanic_id.present?
      mechanic = User.find(mechanic_id)

      # Create or update MechanicAssignment
      assignment = MechanicAssignment.find_or_initialize_by(
        inspection_job: @job,
        mechanic: mechanic
      )

      assignment.update!(
        status: 'assigned',
        started_at: Time.current,
        mechanic_notes: "Assigned by #{current_user.name}"
      )

      @job.update!(
        assigned_mechanic: mechanic,
        assigned_at: Time.current,
        status: 'assigned'
      )

      Notification.create!(
        user: mechanic,
        title: "New Job Assigned",
        message: "Job ##{@job.id} has been assigned to you",
        link: vmcott_mechanic_job_path(@job),
        notification_type: 'info',
        notifiable: @job
      )

      flash[:notice] = "Job assigned to #{mechanic.name}."
    else
      flash[:alert] = "Could not assign job."
    end

    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def reassign_job
    @job = InspectionJob.find(params[:id])
    mechanic_id = params[:mechanic_id]
    reason = params[:reason]

    if mechanic_id.present?
      old_mechanic = @job.assigned_mechanic
      new_mechanic = User.find(mechanic_id)

      # Update MechanicAssignment
      assignment = MechanicAssignment.find_by(inspection_job: @job)

      if assignment
        assignment.update!(
          mechanic: new_mechanic,
          status: 'assigned',
          mechanic_notes: "#{assignment.mechanic_notes}\nReassigned from #{old_mechanic&.name} by #{current_user.name}: #{reason}"
        )
      else
        MechanicAssignment.create!(
          inspection_job: @job,
          mechanic: new_mechanic,
          status: 'assigned',
          mechanic_notes: "Assigned by #{current_user.name} (reassignment): #{reason}"
        )
      end

      @job.update!(
        assigned_mechanic: new_mechanic,
        reassigned_at: Time.current,
        reassigned_by: current_user,
        reassign_reason: reason
      )

      if old_mechanic
        Notification.create!(
          user: old_mechanic,
          title: "Job Reassigned",
          message: "Job ##{@job.id} has been reassigned to #{new_mechanic.name}",
          link: vmcott_workshop_supervisor_job_path(@job),
          notification_type: 'warning',
          notifiable: @job
        )
      end

      Notification.create!(
        user: new_mechanic,
        title: "Job Reassigned to You",
        message: "Job ##{@job.id} has been reassigned to you. Reason: #{reason}",
        link: vmcott_mechanic_job_path(@job),
        notification_type: 'info',
        notifiable: @job
      )

      flash[:notice] = "Job reassigned to #{new_mechanic.name}."
    else
      flash[:alert] = "Could not reassign job."
    end

    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def block_job
    @job = InspectionJob.find(params[:id])

    if @job.status == 'in_progress'
      # Update MechanicAssignment
      assignment = MechanicAssignment.find_by(inspection_job: @job)
      if assignment
        assignment.update!(
          status: 'blocked',
          mechanic_notes: "#{assignment.mechanic_notes}\nBlocked by #{current_user.name}: #{params[:reason]}"
        )
      end

      @job.update!(
        status: 'blocked',
        blocked_at: Time.current,
        blocked_by: current_user,
        blocked_reason: params[:reason] || "Blocked by supervisor"
      )

      Notification.create!(
        user: @job.assigned_mechanic,
        title: "Job Blocked",
        message: "Job ##{@job.id} has been blocked. Reason: #{params[:reason] || 'Supervisor action'}",
        link: vmcott_workshop_supervisor_job_path(@job),
        notification_type: 'warning',
        notifiable: @job
      )

      flash[:notice] = "Job blocked."
    else
      flash[:alert] = "Job cannot be blocked."
    end

    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def unblock_job
    @job = InspectionJob.find(params[:id])

    if @job.status == 'blocked'
      # Update MechanicAssignment
      assignment = MechanicAssignment.find_by(inspection_job: @job)
      if assignment
        assignment.update!(
          status: 'in_progress',
          mechanic_notes: "#{assignment.mechanic_notes}\nUnblocked by #{current_user.name}"
        )
      end

      @job.update!(
        status: 'in_progress',
        unblocked_at: Time.current,
        unblocked_by: current_user
      )

      Notification.create!(
        user: @job.assigned_mechanic,
        title: "Job Unblocked",
        message: "Job ##{@job.id} has been unblocked. You can resume work.",
        link: vmcott_mechanic_job_path(@job),
        notification_type: 'success',
        notifiable: @job
      )

      flash[:notice] = "Job unblocked."
    else
      flash[:alert] = "Job is not blocked."
    end

    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def send_to_qc
    @job = InspectionJob.find(params[:id])

    # Check if there are any pending parts requests
    pending_parts = @job.parts_requests.where(status: 'requested').exists?

    if pending_parts
      flash[:alert] = "Cannot send to QC. There are pending parts requests that need to be approved or rejected first."
      redirect_to vmcott_workshop_supervisor_job_path(@job) and return
    end

    if @job.status == 'in_progress'
      # Update MechanicAssignment with QC request
      assignment = MechanicAssignment.find_by(inspection_job: @job)
      if assignment
        assignment.update!(
          qc_requested_at: Time.current,
          mechanic_notes: "#{assignment.mechanic_notes}\nQC requested at #{Time.current.strftime('%Y-%m-%d %H:%M')} by #{current_user.name}"
        )
      end

      @job.update!(
        status: 'qc_pending',
        qc_requested_at: Time.current,
        qc_requested_by: current_user
      )

      qc_users.find_each do |user|
        Notification.create!(
          user: user,
          title: "Job Ready for QC",
          message: "Job ##{@job.id} is ready for quality control review",
          link: vmcott_workshop_supervisor_job_path(@job),
          notification_type: 'info',
          notifiable: @job
        )
      end

      flash[:notice] = "Job sent to Quality Control."
    else
      flash[:alert] = "Job cannot be sent to QC (current status: #{@job.status})."
    end

    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def pass_qc
    @job = InspectionJob.find(params[:id])

    if @job.status == 'qc_pending'
      # Update MechanicAssignment with QC result
      assignment = MechanicAssignment.find_by(inspection_job: @job)
      if assignment
        assignment.update!(
          qc_completed_at: Time.current,
          qc_notes: params[:qc_notes],
          status: 'completed',
          completed_at: Time.current,
          mechanic_notes: "#{assignment.mechanic_notes}\nQC PASSED at #{Time.current.strftime('%Y-%m-%d %H:%M')} by #{current_user.name}"
        )
      end

      @job.update!(
        status: 'approved_qc',
        qc_passed_at: Time.current,
        qc_passed_by: current_user,
        qc_notes: params[:qc_notes]
      )

      Notification.create!(
        user: @job.assigned_mechanic,
        title: "QC Passed",
        message: "Job ##{@job.id} has passed quality control",
        link: vmcott_workshop_supervisor_job_path(@job),
        notification_type: 'success',
        notifiable: @job
      )

      flash[:notice] = "Job passed QC."
    else
      flash[:alert] = "Job cannot be marked as passed QC."
    end

    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def fail_qc
    @job = InspectionJob.find(params[:id])
    reason = params[:rework_instructions] || "Quality control failed"

    if @job.status == 'qc_pending'
      # Update MechanicAssignment with QC failure
      assignment = MechanicAssignment.find_by(inspection_job: @job)
      if assignment
        assignment.update!(
          qc_completed_at: Time.current,
          qc_notes: "FAILED: #{reason}",
          status: 'rework_needed',
          mechanic_notes: "#{assignment.mechanic_notes}\nQC FAILED at #{Time.current.strftime('%Y-%m-%d %H:%M')} by #{current_user.name}: #{reason}"
        )
      end

      @job.update!(
        status: 'rework_needed',
        qc_failed_at: Time.current,
        qc_failed_by: current_user,
        qc_failure_reason: reason
      )

      Notification.create!(
        user: @job.assigned_mechanic,
        title: "QC Failed - Rework Required",
        message: "Job ##{@job.id} requires rework. Reason: #{reason}",
        link: vmcott_mechanic_job_path(@job),
        notification_type: 'error',
        notifiable: @job
      )

      flash[:alert] = "Job failed QC. Sent for rework."
    else
      flash[:alert] = "Job cannot be marked as failed QC."
    end

    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def close_job
    @job = InspectionJob.find(params[:id])

    if @job.status == 'approved_qc'
      @job.update!(
        status: 'completed',
        completed_at: Time.current,
        completed_by: current_user
      )

      Notification.create!(
        user: @job.assigned_mechanic,
        title: "Job Completed",
        message: "Job ##{@job.id} has been completed and closed",
        link: vmcott_workshop_supervisor_job_path(@job),
        notification_type: 'success',
        notifiable: @job
      )

      flash[:notice] = "Job closed successfully."
    else
      flash[:alert] = "Job cannot be closed in its current state."
    end

    redirect_to vmcott_workshop_supervisor_jobs_path
  end

  def update_job
    @job = InspectionJob.find(params[:id])
    
    # Check if this is a note addition (from the note modal)
    if params[:commit] == "Add Note" || params[:add_note].present?
      new_note = params[:inspection_job][:notes]
      if new_note.present?
        timestamp = Time.current.strftime("%Y-%m-%d %H:%M")
        current_notes = @job.notes.to_s
        updated_notes = "#{current_notes}\n\n[#{timestamp}] #{current_user.name}: #{new_note}"
        
        if @job.update(notes: updated_notes)
          flash[:notice] = "Note added successfully."
        else
          flash[:alert] = "Failed to add note: #{@job.errors.full_messages.join(', ')}"
        end
      else
        flash[:alert] = "Note cannot be blank."
      end
    else
      # Regular job update from edit modal
      if @job.update(update_job_params)
        flash[:notice] = "Job updated successfully."
      else
        flash[:alert] = "Failed to update job: #{@job.errors.full_messages.join(', ')}"
      end
    end
    
    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def request_update
    @job = InspectionJob.find(params[:id])
    message = params[:message] || "Please provide an update on this job"

    Notification.create!(
      user: @job.assigned_mechanic,
      title: "Update Requested",
      message: "Supervisor requested an update: #{message}",
      link: vmcott_mechanic_job_path(@job),
      notification_type: 'info',
      notifiable: @job
    )

    flash[:notice] = "Update request sent to mechanic."
    redirect_to vmcott_workshop_supervisor_job_path(@job)
  end

  def job_report
    @job = InspectionJob.find(params[:id])
    @work_sessions = @job.job_tasks.flat_map(&:work_sessions)
    @total_hours = @work_sessions.sum(&:duration_hours)
    @parts_used = @job.parts_requests.where(status: 'approved')
    @mechanic_assignment = MechanicAssignment.find_by(inspection_job: @job)

    respond_to do |format|
      format.html { render :report }
      format.pdf { render pdf: "job-#{@job.id}-report" }
    end
  end

  def job_history
    @job = InspectionJob.find(params[:id])
    @history = @job.audit_logs.order(created_at: :desc).limit(50)
    @mechanic_assignment_history = MechanicAssignment.where(inspection_job: @job).order(created_at: :desc)
    render :history
  end

  def print_job
    @job = InspectionJob.find(params[:id])
    @work_sessions = @job.job_tasks.flat_map(&:work_sessions)
    @mechanic_assignment = MechanicAssignment.find_by(inspection_job: @job)
    render :print, layout: false
  end

  # =====================================================
  # HELPER METHODS
  # =====================================================

  private

  def require_workshop_supervisor
    unless current_user.role == 'workshop_supervisor' || current_user.admin?
      redirect_to root_path, alert: "Access denied. Workshop Supervisor privileges required."
    end
  end

  def set_stats
    @stats = {
      # Task stats
      pending_tasks: JobTask.where(status: 'pending').count,
      blocked_tasks: JobTask.where(status: 'blocked').count,
      approved_tasks: JobTask.where(status: 'approved').count,
      completed_tasks_today: JobTask.where(status: 'completed')
                                    .where('completed_at >= ?', Time.current.beginning_of_day)
                                    .count,

      # Job stats
      active_jobs: InspectionJob.where(status: 'in_progress').count,
      pre_check_review: InspectionJob.where(status: 'pre_check_completed').count,
      jobs_completed_today: InspectionJob.where(status: 'completed')
                                        .where('completed_at >= ?', Time.current.beginning_of_day)
                                        .count,

      # Work order stats
      pending_work_orders: WorkOrder.where(status: 'awaiting_approval').count,
      approved_work_orders: WorkOrder.where(status: 'approved').count,

      # Finding stats
      pending_findings: Finding.where(status: 'pending', blocking: true).count,
      critical_findings: Finding.where(severity: 'critical', status: 'pending').count,

      # Parts stats
      pending_parts_requests: PartsRequest.where(status: 'pending_approval').count,
      parts_requests_approved_today: PartsRequest.where(status: 'approved')
                                                .where('approved_at >= ?', Time.current.beginning_of_day)
                                                .count,

      # Mechanic stats
      active_mechanics: User.where(role: 'mechanic', is_active: true).count,
      available_mechanics: User.where(role: 'mechanic', is_active: true)
                              .where.not(id: MechanicAssignment.where(status: 'in_progress').select(:mechanic_id))
                              .count,

      # Workflow stats
      workflow_pending: Inspection.where(status: 'pending_supervisor_review')
                                  .where(workflow_selected_by_id: nil).count,
      workflow_selected_today: Inspection.where.not(workflow_selected_by_id: nil)
                                        .where('workflow_selected_at >= ?', Time.current.beginning_of_day)
                                        .count,

      # Assignment stats
      active_assignments: MechanicAssignment.where(status: 'in_progress').count,
      assignments_completed_today: MechanicAssignment.where(status: 'completed')
                                                    .where('completed_at >= ?', Time.current.beginning_of_day)
                                                    .count,

      # QC stats
      qc_pending: MechanicAssignment.where.not(qc_requested_at: nil)
                                    .where(qc_completed_at: nil).count,
      qc_passed_today: MechanicAssignment.where(status: 'qc_passed')
                                        .where('qc_completed_at >= ?', Time.current.beginning_of_day)
                                        .count,
      qc_failed_today: MechanicAssignment.where(status: 'qc_failed')
                                        .where('qc_completed_at >= ?', Time.current.beginning_of_day)
                                        .count,

      # Rework stats
      rework_needed: InspectionJob.where(status: 'rework_needed').count,

      # Hours stats
      total_hours_today: WorkSession.where(session_type: 'work')
                                    .where('started_at >= ?', Time.current.beginning_of_day)
                                    .sum(:duration_hours),

      # Overall
      overall_completion_rate: calculate_completion_rate,

      # 🔥 NEW STATS FOR 14-STEP WORKFLOW
      pending_job_creation: Inspection.where(status: 'diagnosed').count,
      pending_parts_approval: PartsRequest.where(status: 'pending_approval').count,
      pending_quotation: Inspection.where(status: 'parts_approved').count,
      awaiting_approval: Inspection.where(status: 'awaiting_approval').count,
      pending_additional_findings: Inspection.where(status: 'additional_findings_pending').count,
      qc_pending_inspections: Inspection.where(status: 'ready_for_qc').count
    }
  end

  def calculate_completion_rate
    total_jobs = InspectionJob.count
    completed_jobs = InspectionJob.where(status: 'completed').count
    return 0 if total_jobs == 0
    (completed_jobs.to_f / total_jobs * 100).round(1)
  end

  def update_job_params
    params.require(:inspection_job).permit(:description, :estimated_hours, :priority, :notes)
  end

  def calculate_labor_cost(inspection)
    inspection.inspection_jobs.sum(:estimated_labor_cost).to_f
  end

  def calculate_parts_cost(inspection)
    total = 0.0

    inspection.parts_requests.each do |request|
      if request.part.present?
        price = request.part.sale_price || request.part.cost_price || 0
        total += request.quantity.to_f * price.to_f
      end
    end

    total
  rescue => e
    Rails.logger.error "Error calculating parts cost: #{e.message}"
    0.0
  end

  def timeline_events(inspection)
    events = []

    events << {
      date: inspection.created_at,
      title: "Inspection Created",
      description: "Inspection record created",
      status: inspection.status != 'draft' ? "completed" : "current"
    }

    if inspection.started_at.present?
      events << {
        date: inspection.started_at,
        title: "Work Started",
        description: "Repair work began",
        status: inspection.status == 'in_progress' ? "current" : "completed"
      }
    end

    if inspection.ready_for_pickup_at.present?
      events << {
        date: inspection.ready_for_pickup_at,
        title: "Ready for Pickup",
        description: "Vehicle is ready for pickup",
        status: inspection.status == 'completed' ? "completed" : "current"
      }
    end

    if inspection.completed?
      events << {
        date: inspection.completed_at || inspection.updated_at,
        title: "Completed",
        description: "Vehicle picked up",
        status: "completed"
      }
    end

    events.sort_by { |e| e[:date] || Time.current }
  end

  # =====================================================
  # 🔥 NEW: HELPER NOTIFICATION METHODS
  # =====================================================

  def notify_procurement_for_parts(parts_request)
    procurement_ids = User.where(role: 'procurement').pluck(:id)
    Notification.create!(
      title: "📦 Parts Order Required",
      message: "#{parts_request.quantity}x #{parts_request.part&.name || 'Custom part'} needed for inspection ##{parts_request.inspection_id}",
      link: "/vmcott/procurement/purchase_requests/new?parts_request_id=#{parts_request.id}",
      user_id: procurement_ids,
      notifiable_type: 'PartsRequest',
      notifiable_id: parts_request.id,
      notification_type: 'warning'
    )
  rescue => e
    Rails.logger.error "Failed to create notification: #{e.message}"
  end

  def notify_procurement_for_quotation(inspection)
    procurement_ids = User.where(role: 'procurement').pluck(:id)
    Notification.create!(
      title: "📄 Quotation Required",
      message: "Quotation for #{inspection.vehicle.license_plate} is ready for formal creation.",
      link: "/vmcott/procurement/quotations/new?inspection_id=#{inspection.id}",
      user_id: procurement_ids,
      notifiable_type: 'Inspection',
      notifiable_id: inspection.id,
      notification_type: 'info'
    )
  rescue => e
    Rails.logger.error "Failed to create notification: #{e.message}"
  end

  def disable_all_caching
    expires_now

    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0, private"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    response.headers["Turbo-Visit-Control"] = "reload"
    response.headers["Turbo-Cache-Control"] = "no-cache"
    response.headers["X-Accel-Expires"] = "0"
    response.headers["Surrogate-Control"] = "no-store"

    @_cache_hit = false

    if Rails.env.development?
      Rails.logger.debug "🚫 Cache disabled for #{controller_name}##{action_name}"
    end
  end
end and send me the full revised customer portal # app/controllers/customer_portal_controller.rb
class CustomerPortalController < ApplicationController
  layout 'customer_portal'
  
  skip_before_action :authenticate_user!
  skip_before_action :verify_authenticity_token, only: [:authenticate]
  before_action :authenticate_customer, only: [:dashboard, :quotation, :approve, :status, :logout]
  before_action :set_customer_reception, only: [:dashboard, :status]
  before_action :set_quotation, only: [:quotation, :approve]
  before_action :authorize_quotation_access, only: [:quotation, :approve]
  
  # Helper methods
  helper_method :status_badge_color, :work_progress_percentage, :current_customer_reception

  # VMCOTT Contact Information
  VMCOTT_PHONE = "868-625-1234"
  VMCOTT_EMAIL = "service@vmcott.com"
  VMCOTT_ADDRESS = "Golden Grove Road, Piarco, Trinidad"

  def login
    if session[:customer_token].present? && current_customer_reception.present?
      redirect_to customer_dashboard_path and return
    end
  end

  def authenticate
    vehicle = Vehicle.find_by(license_plate: params[:license_plate])
    reception = ReceptionLog.find_by(
      vehicle_id: vehicle&.id,
      receipt_number: params[:receipt_number]
    )
    
    if reception
      token = SecureRandom.hex(32)
      reception.update(
        portal_access_token: token,
        portal_access_expires_at: 30.days.from_now,
        customer_email: params[:email],
        customer_phone: params[:phone],
        customer_name: params[:customer_name]
      )
      
      session[:customer_token] = token
      session[:customer_log_id] = reception.id
      
      redirect_to customer_dashboard_path, notice: "Welcome! You can track your vehicle repair here."
    else
      flash.now[:alert] = "Invalid license plate or receipt number. Please check and try again."
      render :login
    end
  end

  def recover
    # Show recovery form
  end

  def send_recovery
    @reception = ReceptionLog.find_by(customer_email: params[:email]) if params[:email].present?
    @reception ||= ReceptionLog.find_by(customer_phone: params[:phone]) if params[:phone].present?
    
    if @reception
      @reception.send_recovery_email!
      flash[:notice] = "Recovery email sent to #{@reception.customer_email}. Please check your inbox."
      redirect_to customer_login_path
    else
      flash[:alert] = "No records found with that email or phone number. Please contact VMCOTT for assistance."
      render :recover
    end
  end

  def contact_support
    @vmcott_phone = VMCOTT_PHONE
    @vmcott_email = VMCOTT_EMAIL
    @vmcott_address = VMCOTT_ADDRESS
  end

  def dashboard
    @reception = @customer_reception
    @vehicle = @reception&.vehicle
    @condition_report = @reception&.condition_report
    @inspection = Inspection.find_by(vehicle: @vehicle) if @vehicle
    @jobs = @inspection&.inspection_jobs || []
    @parts_requests = @inspection&.parts_requests || []
    @quotation = Quotation.find_by(vehicle: @vehicle) if @vehicle
    @inspection_progress = work_progress_percentage(@inspection)
    @vmcott_phone = VMCOTT_PHONE
  end

  def quotation
    @quotation = Quotation.find(params[:id])
    @inspection = Inspection.find_by(vehicle: @quotation.vehicle) if @quotation.vehicle
    @jobs = @quotation.quotation_jobs
    @parts = @quotation.quotation_job_parts
    @total_cost = @quotation.amount || @quotation.quotation_jobs.sum(&:total_labor_cost) + @quotation.quotation_job_parts.sum(&:total_price)
  end

  def approve
    @quotation = Quotation.find(params[:id])
    
    if params[:approve_all].present?
      # Approve all jobs
      @quotation.quotation_jobs.update_all(client_approved: true, client_approved_at: Time.current)
      @quotation.update(status: 'approved', approved_at: Time.current)
      flash[:notice] = "All jobs approved. Work will begin shortly."
      
    elsif params[:approved_jobs].present?
      # Approve selected jobs
      approved_ids = params[:approved_jobs]
      @quotation.quotation_jobs.where(id: approved_ids).update_all(client_approved: true, client_approved_at: Time.current)
      @quotation.quotation_jobs.where.not(id: approved_ids).update_all(client_approved: false)
      
      if approved_ids.length == @quotation.quotation_jobs.count
        @quotation.update(status: 'approved', approved_at: Time.current)
        flash[:notice] = "All jobs approved. Work will begin shortly."
      else
        @quotation.update(status: 'partially_approved', approved_at: Time.current)
        flash[:notice] = "#{approved_ids.length} job(s) approved. The remaining jobs will not be performed."
      end
      
    else
      flash[:alert] = "Please select at least one job to approve."
      redirect_to customer_quotation_path(@quotation) and return
    end
    
    # Notify procurement that customer approved
    Notification.create!(
      title: "Quotation Approved by Customer",
      message: "Customer has approved #{@quotation.quotation_jobs.where(client_approved: true).count} out of #{@quotation.quotation_jobs.count} jobs for vehicle #{@quotation.vehicle&.license_plate}",
      link: "/vmcott/procurement/quotations/#{@quotation.id}",
      user_id: User.where(role: 'procurement').pluck(:id)
    )
    
    redirect_to customer_dashboard_path, notice: flash[:notice]
  end

  def status
    @reception = @customer_reception
    @inspection = Inspection.find_by(vehicle: @reception&.vehicle) if @reception&.vehicle
    @vehicle = @reception&.vehicle
    @jobs = @inspection&.inspection_jobs || []
    @parts_requests = @inspection&.parts_requests || []
    @timeline = build_timeline(@reception, @inspection)
  end

  def logout
    session[:customer_token] = nil
    session[:customer_log_id] = nil
    redirect_to customer_login_path, notice: "You have been logged out."
  end

  private

  def authenticate_customer
    token = session[:customer_token] || params[:token]
    
    if token.blank?
      redirect_to customer_login_path, alert: "Please log in to continue." and return false
    end
    
    @reception = ReceptionLog.find_by(portal_access_token: token)
    
    if @reception.nil?
      session[:customer_token] = nil
      redirect_to customer_login_path, alert: "Invalid session. Please log in again." and return false
    end
    
    if @reception.portal_access_expires_at.present? && @reception.portal_access_expires_at < Time.current
      session[:customer_token] = nil
      redirect_to customer_login_path, alert: "Your session has expired. Please log in again." and return false
    end
    
    if params[:token].present? && session[:customer_token].blank?
      session[:customer_token] = token
      session[:customer_log_id] = @reception.id
    end
    
    true
  end

  def set_customer_reception
    @customer_reception = current_customer_reception
    if @customer_reception.nil?
      redirect_to customer_login_path, alert: "Session expired. Please log in again."
    end
  end

  def set_quotation
    @quotation = Quotation.find_by(id: params[:id])
    if @quotation.nil?
      redirect_to customer_dashboard_path, alert: "Quotation not found."
    end
  end

  def authorize_quotation_access
    return unless @quotation && @customer_reception
    
    unless @quotation.vehicle_id == @customer_reception.vehicle_id
      redirect_to customer_dashboard_path, alert: "Access denied. You can only view quotations for your vehicle."
    end
  end

  def current_customer_reception
    return nil unless session[:customer_token]
    @current_customer_reception ||= ReceptionLog.find_by(portal_access_token: session[:customer_token])
  end

  def build_timeline(reception, inspection)
    timeline = []
    
    timeline << {
      date: reception.received_at,
      title: "Vehicle Received",
      description: "Your vehicle was received at VMCOTT",
      icon: "bi-box-arrow-in-right",
      status: "completed"
    }
    
    if reception.condition_report&.completed?
      timeline << {
        date: reception.condition_report.signed_at || reception.created_at,
        title: "Condition Report Completed",
        description: "Initial condition assessment completed",
        icon: "bi-clipboard-check",
        status: "completed"
      }
    end
    
    if inspection.present?
      timeline << {
        date: inspection.created_at,
        title: "Inspection Started",
        description: "Technical inspection in progress",
        icon: "bi-search",
        status: inspection.status != 'pending_inspection' ? "completed" : "in_progress"
      }
      
      if inspection.inspection_jobs.any?
        completed_jobs = inspection.inspection_jobs.where.not(completed_at: nil).count
        total_jobs = inspection.inspection_jobs.count
        
        timeline << {
          date: inspection.inspection_jobs.where.not(completed_at: nil).first&.completed_at || Time.current,
          title: "Repair Work",
          description: "#{completed_jobs} of #{total_jobs} repair jobs completed",
          icon: "bi-tools",
          status: completed_jobs == total_jobs ? "completed" : "in_progress"
        }
      end
      
      if inspection.status == 'ready_for_pickup' || inspection.status == 'completed'
        timeline << {
          date: inspection.ready_for_pickup_at || inspection.updated_at,
          title: "Quality Control Passed",
          description: "Vehicle passed quality control inspection",
          icon: "bi-check-circle",
          status: "completed"
        }
      end
      
      if inspection.ready_for_pickup_at.present?
        timeline << {
          date: inspection.ready_for_pickup_at,
          title: "Ready for Pickup",
          description: "Your vehicle is ready for pickup",
          icon: "bi-truck",
          status: "completed"
        }
      end
    end
    
    timeline.sort_by { |t| t[:date] || Time.current }
  end

  def status_badge_color(status)
    case status.to_s
    when 'pending_inspection' then 'secondary'
    when 'approved_for_repair' then 'success'
    when 'in_progress' then 'warning'
    when 'parts_coordinator_review' then 'info'
    when 'ready_for_qc' then 'info'
    when 'qc_completed' then 'success'
    when 'ready_for_pickup' then 'success'
    when 'completed' then 'success'
    when 'approved' then 'success'
    when 'partially_approved' then 'warning'
    else 'primary'
    end
  end

  def work_progress_percentage(inspection)
    return 0 unless inspection.present?
    total_jobs = inspection.inspection_jobs.count
    return 0 if total_jobs == 0
    completed_jobs = inspection.inspection_jobs.where.not(completed_at: nil).count
    ((completed_jobs.to_f / total_jobs) * 100).round
  end
end and send me the full revised mechanic controller too # app/controllers/vmcott/mechanic/dashboard_controller.rb
class Vmcott::Mechanic::DashboardController < ApplicationController
  # Skip the dashboard caching for this controller
  skip_around_action :cache_dashboard_data, if: :dashboard_controller?
  
  before_action :authenticate_user!
  before_action :require_mechanic
  before_action :set_job_context, only: [:show_job, :start_job, :update_progress, :log_parts, :request_qc, :request_part, :start_pre_check, :submit_pre_check]
  before_action :ensure_can_start_job, only: [:start_job]
  before_action :ensure_can_request_parts, only: [:log_parts, :request_part]
  before_action :ensure_can_do_pre_check, only: [:start_pre_check, :submit_pre_check]
  
  # Disable all caching for this controller
  before_action :disable_caching

  # =====================================================
  # MAIN DASHBOARD
  # =====================================================

  def index
    # Set headers to prevent caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    # ========================================
    # 🔧 PHASE 3: DIAGNOSIS QUEUE (FIXED)
    # Inspections that are 'inspected' and need diagnosis
    # ========================================
    @pending_diagnosis = Inspection
      .where(status: 'inspected')  # Use 'inspected' status
      .where(diagnosis_completed_at: nil)
      .includes(:vehicle, :inspector)
      .order(created_at: :asc)  # Oldest first
    
    @pending_diagnosis_count = @pending_diagnosis.count
    
    # ========================================
    # MY ASSIGNED JOBS - What supervisor assigned to me
    # ========================================
    @assigned_jobs = MechanicAssignment.includes(inspection_job: { inspection: :vehicle })
                                      .where(mechanic_id: current_user.id, status: ['assigned', 'in_progress'])
                                      .order(created_at: :asc)

    # ========================================
    # JOBS READY TO BE TAKEN (No assigned mechanic)
    # ========================================
    @ready_jobs = InspectionJob
      .where(status: 'pending_approval')
      .where(assigned_mechanic_id: nil)
      .where(completed_at: nil)
      .includes(inspection: :vehicle)
      .order(created_at: :desc)
      .limit(20)

    # ========================================
    # JOBS NEEDING PRE-CHECK - Jobs assigned but not pre-checked
    # ========================================
    @pre_check_jobs = InspectionJob.includes(inspection: :vehicle)
                                  .where(assigned_mechanic_id: current_user.id)
                                  .where(status: 'assigned')
                                  .order(created_at: :asc)

    # ========================================
    # JOBS READY FOR WORK - Pre-check completed and approved
    # ========================================
    @ready_for_work = InspectionJob.includes(inspection: :vehicle)
                                  .where(assigned_mechanic_id: current_user.id)
                                  .where(status: 'approved_for_work')
                                  .order(created_at: :asc)

    # ========================================
    # WAITING JOBS - Jobs assigned to others or pending approval
    # ========================================
    @waiting_jobs = InspectionJob.includes(inspection: :vehicle)
                                .where(assigned_mechanic_id: nil, completed_at: nil)
                                .where(verification_status: 'approved')
                                .joins(:inspection)
                                .where(inspections: { status: 'approved' })
                                .where.not(id: @assigned_jobs.map(&:inspection_job_id))
                                .distinct
                                .order(created_at: :desc)
                                .limit(20)

    # ========================================
    # TAKEN BY OTHERS - Jobs other mechanics are doing
    # ========================================
    @other_mechanics_jobs = InspectionJob.includes(inspection: :vehicle)
                                        .where.not(assigned_mechanic_id: nil)
                                        .where.not(assigned_mechanic_id: current_user.id)
                                        .where(completed_at: nil)
                                        .order(created_at: :desc)
                                        .limit(20)

    # ========================================
    # QC PENDING JOBS - Jobs that need quality check
    # ========================================
    @qc_pending_jobs = InspectionJob.includes(inspection: { vehicle: :agency })
                                .joins(:inspection)
                                .where.not(completed_at: nil)
                                .where(inspections: { status: ['qc_pending'] })
                                .order(completed_at: :desc)
                                .limit(20)

    # ========================================
    # STATS CARDS - Quick numbers
    # ========================================
    @completed_today = MechanicAssignment.where(mechanic_id: current_user.id)
                                        .where('completed_at >= ?', Date.current.beginning_of_day)
                                        .count
    
    @qc_pending = @qc_pending_jobs.count
    @pre_check_needed = @pre_check_jobs.count
    @ready_to_work = @ready_for_work.count
    @available_jobs_count = @ready_jobs.count
                          
    @recently_completed = InspectionJob.where(assigned_mechanic_id: current_user.id)
                                      .where.not(completed_at: nil)
                                      .order(completed_at: :desc)
                                      .limit(10)

    # ========================================
    # WORKFLOW STATUS VARIABLES (For the progress bar)
    # ========================================
    @inspections_complete = Inspection.where(status: ['inspected', 'diagnosed', 'approved']).count
    @parts_complete = PartsRequest.where(status: ['approved', 'received']).count
    @parts_pending = PartsRequest.where(status: ['requested', 'pending_approval']).count
    @assigned_jobs_count = @assigned_jobs.count
    
    @repairs_complete = InspectionJob.where.not(completed_at: nil)
                                    .where('inspection_jobs.completed_at >= ?', Time.current.beginning_of_day)
                                    .count
    
    @qc_complete = InspectionJob.where(verification_status: 'verified')
                                .where('inspection_jobs.verified_at > ?', 24.hours.ago)
                                .count
    
    @ready_for_pickup = Inspection.where(status: 'ready_for_pickup').count
    
    @new_jobs_available = @ready_jobs.where('inspection_jobs.created_at > ?', 1.hour.ago).count

    # For backward compatibility
    @my_jobs = @assigned_jobs
    @taken_jobs = @other_mechanics_jobs
    @ready_to_take_jobs = @waiting_jobs
    @not_ready_jobs = []
    
    # Log for debugging
    Rails.logger.info "Mechanic Dashboard - Diagnosis count: #{@pending_diagnosis_count}"
    Rails.logger.info "Mechanic Dashboard - Ready jobs: #{@ready_jobs.count}"
    Rails.logger.info "Mechanic Dashboard - Assigned jobs: #{@assigned_jobs.count}"
    
  rescue => e
    Rails.logger.error "Error in mechanic dashboard: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    flash[:alert] = "An error occurred while loading the dashboard: #{e.message}"
    
    # Set default values
    @assigned_jobs = []
    @ready_jobs = []
    @pre_check_jobs = []
    @ready_for_work = []
    @waiting_jobs = []
    @other_mechanics_jobs = []
    @qc_pending_jobs = []
    @pending_diagnosis = []
    @pending_diagnosis_count = 0
    @completed_today = 0
    @qc_pending = 0
    @pre_check_needed = 0
    @ready_to_work = 0
    @available_jobs_count = 0
    @recently_completed = []
    @my_jobs = []
    @taken_jobs = []
    @ready_to_take_jobs = []
    @not_ready_jobs = []
    @inspections_complete = 0
    @parts_complete = 0
    @parts_pending = 0
    @assigned_jobs_count = 0
    @repairs_complete = 0
    @qc_complete = 0
    @ready_for_pickup = 0
    @new_jobs_available = 0
  end

  # =====================================================
  # PHASE 3: DIAGNOSIS METHODS
  # =====================================================

  def diagnosis_index
    @pending_diagnosis = Inspection
      .where(status: 'inspected')
      .where(diagnosis_completed_at: nil)
      .includes(:vehicle, :inspector)
      .order(created_at: :desc)
      .page(params[:page])
      .per(20)
    
    disable_caching
    render :diagnosis_index
  end

  def diagnosis_show
    @inspection = Inspection.find(params[:id])
    
    # Check if inspection is ready for diagnosis
    unless @inspection.status == 'inspected'
      flash[:alert] = "This inspection is not ready for diagnosis (current status: #{@inspection.status})"
      redirect_to vmcott_mechanic_dashboard_path and return
    end
    
    @vehicle = @inspection.vehicle
    @inspector_notes = @inspection.notes
    @inspector_findings = @inspection.findings.where(finding_type: 'inspector')
    @inspector_recommendations = @inspection.inspection_recommendations
    
    disable_caching
    render :diagnosis_show
  end

  def diagnosis_create
    @inspection = Inspection.find(params[:inspection_id])
    
    # Validate diagnosis notes presence
    if params[:diagnosis_notes].blank?
      flash[:alert] = "Diagnosis notes cannot be blank. Please add your findings and recommendations."
      redirect_to vmcott_mechanic_diagnosis_show_path(@inspection) and return
    end
    
    # Check if inspection is ready for diagnosis
    unless @inspection.status == 'inspected'
      flash[:alert] = "This inspection is not ready for diagnosis"
      redirect_to vmcott_mechanic_dashboard_path and return
    end
    
    begin
      ActiveRecord::Base.transaction do
        # Handle findings if present
        if params[:findings].present?
          findings_array = if params[:findings].is_a?(Hash)
            params[:findings].values
          else
            params[:findings]
          end
          
          findings_array.each do |finding|
            next unless finding.is_a?(Hash)
            next if finding[:description].blank?
            
            @inspection.findings.create!(
              description: finding[:description],
              finding_type: 'mechanic_diagnosis',
              severity: finding[:severity] || 'normal',
              blocking: finding[:blocking] == 'true',
              created_by: current_user,
              metadata: {
                root_cause: finding[:root_cause],
                complexity: finding[:complexity] || 'moderate',
                estimated_hours: finding[:estimated_hours],
                suggested_parts: finding[:suggested_parts]
              }
            )
          end
        end
        
        # Update status to 'diagnosed'
        update_result = @inspection.update(
          status: 'diagnosed',
          diagnosis_notes: params[:diagnosis_notes],
          diagnosis_completed_at: Time.current,
          assigned_mechanic_id: current_user.id
        )
        
        unless update_result
          raise "Failed to update inspection: #{@inspection.errors.full_messages.join(', ')}"
        end
        
        # Notify supervisor that diagnosis is complete
        supervisor_ids = User.where(role: 'workshop_supervisor').pluck(:id)
        if supervisor_ids.any?
          Notification.create!(
            title: "📋 Diagnosis Complete",
            message: "Diagnosis for #{@inspection.vehicle.license_plate} is complete. Please create jobs.",
            link: "/vmcott/workshop_supervisor/inspections/#{@inspection.id}/job_creation",
            user_id: supervisor_ids,
            notifiable_type: 'Inspection',
            notifiable_id: @inspection.id,
            notification_type: 'info'
          )
        end
        
        # Log success
        Rails.logger.info "✅ Diagnosis completed for inspection ##{@inspection.id} by #{current_user.name}"
        
        flash[:notice] = "✅ Diagnosis completed successfully! Supervisor will now create jobs."
        redirect_to vmcott_mechanic_dashboard_path and return
      end
    rescue => e
      Rails.logger.error "Error in diagnosis_create: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      flash[:alert] = "Error saving diagnosis: #{e.message}"
      redirect_to vmcott_mechanic_diagnosis_show_path(@inspection) and return
    end
  end

  # =====================================================
  # JOB METHODS
  # =====================================================

  def show_job
    @job = InspectionJob.includes(inspection: :vehicle, parts_requests: [:part])
                        .find(params[:id])
    @assignment = MechanicAssignment.find_by(inspection_job_id: @job.id, mechanic_id: current_user.id)
    @parts_used = @job.parts_requests.where(status: ['received', 'issued'])
    @pre_check_data = {
      notes: @job.pre_check_notes,
      completed_at: @job.pre_check_completed_at,
      findings: @job.additional_findings
    }
    
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end

  # 🔥 FIX: This method now actually assigns the job to the mechanic
  def assign_self
    @job = InspectionJob.find(params[:id])
    
    # Check if job is already assigned
    if @job.assigned_mechanic_id.present?
      redirect_to vmcott_mechanic_job_path(@job), alert: "This job is already assigned to another mechanic."
      return
    end
    
    # Assign the job to current mechanic
    @job.update!(
      assigned_mechanic_id: current_user.id,
      status: 'assigned'  # Change status to assigned
    )
    
    # Create MechanicAssignment record
    MechanicAssignment.find_or_create_by!(
      inspection_job_id: @job.id,
      mechanic_id: current_user.id
    ).update!(
      status: 'assigned',
      started_at: Time.current,
      mechanic_notes: "Assigned by mechanic at #{Time.current}"
    )
    
    flash[:notice] = "✅ Job ##{@job.id} assigned to you successfully!"
    redirect_to vmcott_mechanic_job_path(@job)
  rescue => e
    Rails.logger.error "Error assigning job: #{e.message}"
    flash[:alert] = "Error assigning job: #{e.message}"
    redirect_to vmcott_mechanic_dashboard_path
  end

  # =====================================================
  # PRE-CHECK METHODS
  # =====================================================
  
  def start_pre_check
    @job = InspectionJob.find(params[:id])
    
    unless @job.assigned_mechanic_id == current_user.id
      redirect_to vmcott_mechanic_dashboard_path, alert: "You cannot start pre-check for a job not assigned to you."
      return
    end
    
    unless @job.status == 'assigned'
      redirect_to vmcott_mechanic_job_path(@job), alert: "This job is not ready for pre-check."
      return
    end
    
    @job.start_pre_check!(current_user)
    
    redirect_to pre_check_vmcott_mechanic_job_path(@job), notice: "Pre-check started. Please inspect the vehicle thoroughly."
  end

  def pre_check
    @job = InspectionJob.find(params[:id])
    
    unless @job.assigned_mechanic_id == current_user.id
      redirect_to vmcott_mechanic_dashboard_path, alert: "Access denied."
      return
    end
    
    unless @job.status == 'pre_check_in_progress'
      redirect_to vmcott_mechanic_job_path(@job), alert: "Pre-check not in progress."
      return
    end
    
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    render :pre_check
  end

  def submit_pre_check
    @job = InspectionJob.find(params[:id])
    
    unless @job.assigned_mechanic_id == current_user.id
      redirect_to vmcott_mechanic_dashboard_path, alert: "Access denied."
      return
    end
    
    additional_findings = []
    
    if params[:additional_findings].present?
      additional_findings = params[:additional_findings].map do |finding|
        {
          description: finding[:description],
          severity: finding[:severity],
          estimated_hours: finding[:estimated_hours],
          created_at: Time.current,
          created_by: current_user.name
        }
      end
    end
    
    @job.complete_pre_check!(params[:notes], additional_findings)
    
    redirect_to vmcott_mechanic_dashboard_path, 
                notice: "✅ Pre-check completed. #{additional_findings.count} additional findings sent to supervisor for approval."
  end

  def start_job
    if @job.assigned_mechanic_id != current_user.id
      redirect_to vmcott_mechanic_dashboard_path, alert: "You cannot start a job that isn't assigned to you."
      return
    end
    
    # Allow starting from 'assigned' or 'approved_for_work' status
    unless @job.status == 'assigned' || @job.status == 'approved_for_work'
      redirect_to vmcott_mechanic_job_path(@job), alert: "This job is not ready to start (current status: #{@job.status})."
      return
    end
    
    assignment = MechanicAssignment.find_or_initialize_by(
      inspection_job_id: @job.id,
      mechanic_id: current_user.id
    )
    
    assignment.status = 'in_progress'
    assignment.started_at = Time.current
    assignment.save!
    
    @job.update!(started_at: Time.current, status: :in_progress)
    
    redirect_to vmcott_mechanic_job_path(@job), notice: "✅ Job started successfully. Good luck!"
  rescue => e
    Rails.logger.error "Error in start_job: #{e.message}"
    flash[:alert] = "Error starting job: #{e.message}"
    redirect_to vmcott_mechanic_job_path(@job)
  end

  def update_progress
    if @job.assigned_mechanic_id != current_user.id
      redirect_to vmcott_mechanic_dashboard_path, alert: "You cannot update a job that isn't assigned to you."
      return
    end
    
    if params[:progress_update].blank?
      redirect_to vmcott_mechanic_job_path(@job), alert: "Progress note cannot be blank."
      return
    end
    
    assignment = MechanicAssignment.find_by(inspection_job_id: @job.id, mechanic_id: current_user.id)
    
    if assignment.nil?
      redirect_to vmcott_mechanic_job_path(@job), alert: "Assignment record not found."
      return
    end
    
    assignment.update(
      mechanic_notes: "#{assignment.mechanic_notes}\n[#{Time.current.strftime('%H:%M %m/%d')}] #{params[:progress_update]}"
    )
    
    flash[:notice] = "Progress updated successfully."
    redirect_to vmcott_mechanic_job_path(@job)
  rescue => e
    Rails.logger.error "Error in update_progress: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    redirect_to vmcott_mechanic_job_path(@job), alert: "An error occurred while updating progress: #{e.message}"
  end

  def log_parts
    if @job.assigned_mechanic_id != current_user.id
      render json: { success: false, message: "You cannot log parts for a job that isn't assigned to you." }, status: :unauthorized
      return
    end
    
    assignment = MechanicAssignment.find_by(inspection_job_id: @job.id, mechanic_id: current_user.id)
    unless assignment&.in_progress?
      render json: { success: false, message: "Parts can only be logged when job is in progress." }, status: :unauthorized
      return
    end
    
    part = Part.find_by(id: params[:part_id])
    qty = params[:quantity].to_i

    if part.nil?
      render json: { success: false, message: "Part not found" }, status: :not_found
      return
    end

    if qty <= 0
      render json: { success: false, message: "Quantity must be greater than zero" }, status: :unprocessable_entity
      return
    end

    if part.current_stock < qty
      render json: { success: false, message: "Insufficient stock. Available: #{part.current_stock}" }, status: :unprocessable_entity
      return
    end

    part.update!(current_stock: part.current_stock - qty)
    
    if assignment
      assignment.update(
        mechanic_notes: "#{assignment.mechanic_notes}\n[PARTS] Used #{qty}x #{part.name} (Stock left: #{part.current_stock})"
      )
    end
    
    job_part = InspectionJobPart.find_or_create_by!(
      inspection_job_id: @job.id,
      part_id: part.id
    ) do |jp|
      jp.quantity = qty
      jp.notes = "Used by mechanic #{current_user.name}"
    end

    render json: { success: true, new_stock: part.current_stock, message: "#{qty}x #{part.name} logged successfully" }
  rescue => e
    Rails.logger.error "Error in log_parts: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: { success: false, message: "An error occurred: #{e.message}" }, status: :internal_server_error
  end

  def request_part
    if @job.assigned_mechanic_id != current_user.id
      redirect_to vmcott_mechanic_dashboard_path, alert: "Access Denied: You cannot request parts for a job that isn't assigned to you."
      return
    end
    
    assignment = MechanicAssignment.find_by(inspection_job_id: @job.id, mechanic_id: current_user.id)
    unless assignment&.in_progress?
      redirect_to vmcott_mechanic_job_path(@job), alert: "Action Not Permitted: Parts can only be requested when job is in progress."
      return
    end

    if params[:quantity].blank? || params[:quantity].to_i <= 0
      redirect_to vmcott_mechanic_job_path(@job), alert: "Invalid Quantity: Please enter a valid quantity greater than zero."
      return
    end

    quantity = params[:quantity].to_i

    if params[:part_type] == 'inventory'
      if params[:part_id].blank?
        redirect_to vmcott_mechanic_job_path(@job), alert: "Selection Required: Please select a part from the inventory."
        return
      end
      
      part = Part.find_by(id: params[:part_id])
      if part.nil?
        redirect_to vmcott_mechanic_job_path(@job), alert: "Part Not Found: The selected part could not be located in the inventory."
        return
      end
      
      part_name = part.name
      
      existing_request = PartsRequest.find_by(
        inspection_id: @job.inspection_id,
        part_id: part.id,
        status: 'requested'
      )
      
      if existing_request
        new_quantity = existing_request.quantity + quantity
        existing_request.update(quantity: new_quantity)
        
        assignment.update(
          mechanic_notes: "#{assignment.mechanic_notes}\n[REQUEST] Added #{quantity}x #{part_name} to existing request (Total: #{new_quantity})"
        )
        
        flash[:notice] = "✅ Quantity Updated\n\n" \
                        "Part: #{part_name}\n" \
                        "Added: #{quantity} units\n" \
                        "Total: #{new_quantity} units\n\n" \
                        "Waiting for supervisor approval."
      else
        # Create new parts request
        PartsRequest.create!(
          inspection_job_id: @job.id,
          inspection_id: @job.inspection_id,
          part_id: part.id,
          quantity: quantity,
          status: 'requested',
          unit_price: part.cost_price || 0,
          requested_by: current_user
        )
        
        assignment.update(
          mechanic_notes: "#{assignment.mechanic_notes}\n[REQUEST] Requested #{quantity}x #{part_name}"
        )
        
        flash[:notice] = "📋 Request Submitted\n\n" \
                        "Part: #{part_name}\n" \
                        "Quantity: #{quantity} units\n\n" \
                        "Waiting for supervisor approval."
      end
      
    elsif params[:part_type] == 'custom'
      if params[:custom_part_name].blank?
        redirect_to vmcott_mechanic_job_path(@job), alert: "Required Field: Please enter a name for the custom part."
        return
      end
      
      part_name = params[:custom_part_name]
      
      # Check for existing pending request for this custom part
      existing_request = PartsRequest.find_by(
        inspection_id: @job.inspection_id,
        custom_part_name: part_name,
        status: 'requested'
      )
      
      if existing_request
        new_quantity = existing_request.quantity + quantity
        existing_request.update(quantity: new_quantity)
        
        assignment.update(
          mechanic_notes: "#{assignment.mechanic_notes}\n[REQUEST] Added #{quantity}x #{part_name} (custom) to existing request (Total: #{new_quantity})"
        )
        
        flash[:notice] = "✅ Quantity Updated\n\n" \
                        "Part: #{part_name} (Custom)\n" \
                        "Added: #{quantity} units\n" \
                        "Total: #{new_quantity} units\n\n" \
                        "Waiting for supervisor approval."
      else
        # Create custom part request
        PartsRequest.create!(
          inspection_job_id: @job.id,
          inspection_id: @job.inspection_id,
          custom_part_name: part_name,
          quantity: quantity,
          status: 'requested',
          requested_by: current_user
        )
        
        assignment.update(
          mechanic_notes: "#{assignment.mechanic_notes}\n[REQUEST] Requested #{quantity}x #{part_name} (custom part)"
        )
        
        flash[:notice] = "📦 Request Submitted\n\n" \
                        "Part: #{part_name} (Custom)\n" \
                        "Quantity: #{quantity} units\n\n" \
                        "Supervisor has been notified."
      end
    else
      redirect_to vmcott_mechanic_job_path(@job), alert: "Selection Required: Please select a part type (Inventory or Custom)."
      return
    end

    redirect_to vmcott_mechanic_job_path(@job), notice: flash[:notice]
  rescue => e
    Rails.logger.error "Error in request_part: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    flash[:alert] = "System Error: #{e.message}"
    redirect_to vmcott_mechanic_job_path(@job)
  end

  def request_qc
    if @job.assigned_mechanic_id != current_user.id
      redirect_to vmcott_mechanic_dashboard_path, alert: "You cannot request QC for a job that isn't assigned to you."
      return
    end
    
    inspection = @job&.inspection
    
    if @job.nil? || inspection.nil?
      redirect_to vmcott_mechanic_dashboard_path, alert: "Job or inspection not found."
      return
    end
    
    assignment = MechanicAssignment.find_by(inspection_job_id: @job.id, mechanic_id: current_user.id)
    if assignment
      assignment.update!(
        status: 'completed', 
        completed_at: Time.current
      )
    end
    
    @job.update_columns(completed_at: Time.current)

    if inspection.inspection_jobs.where(completed_at: nil).none?
      inspection.update!(status: 'qc_pending')
      
      User.where(role: ['inspector', 'admin']).each do |inspector|
        Notification.create!(
          user: inspector,
          title: "QC Required for #{inspection.vehicle&.license_plate || 'Vehicle'}",
          message: "All jobs for inspection ##{inspection.id} are completed. Please perform final QC.",
          notifiable: inspection,
          link: vmcott_inspector_qc_path(inspection)
        ) rescue nil
      end
      
      flash[:notice] = "Job completed and QC requested. All jobs for this vehicle are now complete."
    else
      flash[:notice] = "Job completed. Other jobs for this vehicle are still in progress."
    end
    
    flash[:highlight_job_id] = @job.id
    flash[:success] = "Job ##{@job.id} has been marked complete and sent for QC inspection"

    redirect_to vmcott_mechanic_dashboard_path
  rescue => e
    Rails.logger.error "Error in request_qc: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    redirect_to vmcott_mechanic_job_path(@job), alert: "An error occurred while requesting QC: #{e.message}"
  end

  def verification_queue
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    @pending_verification = InspectionJob.includes(inspection: :vehicle)
                                         .where(verification_status: 'pending')
                                         .where(assigned_mechanic_id: nil)
                                         .order(created_at: :desc)
                                         .limit(50)
    
    @recently_verified = InspectionJob.includes(inspection: :vehicle)
                                      .where(verification_status: ['verified', 'rejected', 'different'])
                                      .where('inspection_jobs.verified_at > ?', 24.hours.ago)
                                      .order(verified_at: :desc)
                                      .limit(30)
    
    @verified_today = InspectionJob.where(verification_status: ['verified', 'rejected', 'different'])
                                   .where('inspection_jobs.verified_at > ?', Time.current.beginning_of_day)
                                   .count
    
    @needs_action = InspectionJob.where(verification_status: 'pending').count
    @show_verification_link = @pending_verification.any?
  end

  def verify_job
    @job = InspectionJob.includes(inspection: :vehicle, parts_requests: [:part]).find(params[:id])
    
    if @job.assigned_mechanic_id.present? && @job.assigned_mechanic_id != current_user.id
      redirect_to vmcott_mechanic_dashboard_path, alert: "This job is already assigned to another mechanic."
      return
    end
    
    @job.update(assigned_mechanic_id: current_user.id) if @job.assigned_mechanic_id.nil?
    
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end

  def submit_verification
    @job = InspectionJob.find(params[:id])
    
    if @job.assigned_mechanic_id != current_user.id
      redirect_to vmcott_mechanic_dashboard_path, alert: "You cannot verify a job that isn't assigned to you."
      return
    end

    ActiveRecord::Base.transaction do
      verification_status = params[:verification_status]
      
      @job.update!(
        verification_status: verification_status,
        verified_by_mechanic_id: current_user.id,
        verified_at: Time.current,
        mechanic_notes: params[:mechanic_notes]
      )

      case verification_status
      when 'verified'
        @job.inspection_job_parts.each do |job_part|
          part = job_part.part
          if part && part.current_stock >= job_part.quantity
            PartsRequest.create!(
              inspection: @job.inspection,
              inspection_job: @job,
              part: part,
              quantity: job_part.quantity,
              status: 'requested',
              in_stock: true
            )
          else
            PartsRequest.create!(
              inspection: @job.inspection,
              inspection_job: @job,
              part: part,
              quantity: job_part.quantity,
              status: 'requested',
              in_stock: false,
              custom_part_name: job_part.custom_part_name
            )
          end
        end
        flash[:notice] = "Job verified successfully. Parts requests created."
        
      when 'different'
        corrected_job = @job.inspection.inspection_jobs.create!(
          description: params[:corrected_description],
          recommendation_source: 'mechanic',
          verification_status: 'approved',
          parent_job_id: @job.id,
          priority: @job.priority
        )
        
        if params[:parts].present?
          params[:parts].each do |part_data|
            if part_data[:is_custom] == 'true'
              corrected_job.inspection_job_parts.create!(
                custom_part_name: part_data[:custom_name],
                quantity: part_data[:quantity]
              )
              PartsRequest.create!(
                inspection: @job.inspection,
                inspection_job: corrected_job,
                custom_part_name: part_data[:custom_name],
                quantity: part_data[:quantity],
                status: 'requested',
                in_stock: false
              )
            else
              part = Part.find(part_data[:part_id])
              corrected_job.inspection_job_parts.create!(
                part: part,
                quantity: part_data[:quantity]
              )
              
              if part.current_stock >= part_data[:quantity].to_i
                PartsRequest.create!(
                  inspection: @job.inspection,
                  inspection_job: corrected_job,
                  part: part,
                  quantity: part_data[:quantity],
                  status: 'requested',
                  in_stock: true
                )
              else
                PartsRequest.create!(
                  inspection: @job.inspection,
                  inspection_job: corrected_job,
                  part: part,
                  quantity: part_data[:quantity],
                  status: 'requested',
                  in_stock: false
                )
              end
            end
          end
        end
        
        @job.update!(status: 'superseded')
        flash[:notice] = "Corrected job created based on your findings."
        
      when 'rejected'
        @job.update!(
          completed_at: Time.current,
          status: 'cancelled'
        )
        flash[:notice] = "Job marked as not needed."
      end

      inspection = @job.inspection
      if inspection.inspection_jobs.where(verification_status: 'pending').none?
        if inspection.inspection_jobs.joins(:parts_requests).where(parts_requests: { status: 'requested' }).any?
          inspection.update!(status: 'parts_pending')
          notify_inventory_manager(inspection)
        else
          inspection.update!(status: 'approved')
          notify_mechanics_work_ready(inspection)
        end
      end
    end

    redirect_to vmcott_mechanic_dashboard_path
  rescue => e
    Rails.logger.error "Error in submit_verification: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    flash[:alert] = "An error occurred while submitting verification: #{e.message}"
    redirect_to vmcott_mechanic_verify_job_path(@job)
  end

  def new_additional_finding
    @inspection = Inspection.find(params[:inspection_id])
    
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    unless @inspection.status == 'approved'
      redirect_to vmcott_mechanic_dashboard_path, alert: "Can only report additional findings on approved work."
      return
    end
    
    @job = @inspection.inspection_jobs.new
  end

  def create_additional_finding
    @inspection = Inspection.find(params[:inspection_id])
    @job = InspectionJob.find_by(inspection_id: @inspection.id)
    
    additional_maintenance = @inspection.vehicle.maintenances.create!(
      service_type: "Additional Finding",
      description: params[:description],
      status: "Pending",
      assignment_type: "stores",
      date: Time.current,
      start_date: Time.current,
      end_date: 7.days.from_now,
      notes: "Additional finding during repair of inspection ##{@inspection.id}",
      additional_work: true,
      urgency: :high
    )
    
    notify_finance_for_additional_quotation(additional_maintenance)
    
    if @job.present?
      redirect_to vmcott_mechanic_job_path(@job), notice: "Additional finding logged. Finance will create a new quotation."
    else
      redirect_to vmcott_mechanic_dashboard_path, notice: "Additional finding logged. Finance will create a new quotation."
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Validation error in create_additional_finding: #{e.message}"
    
    if @job.present?
      redirect_to vmcott_mechanic_job_path(@job), alert: "Failed to log additional finding: #{e.record.errors.full_messages.join(', ')}"
    else
      redirect_to vmcott_mechanic_dashboard_path, alert: "Failed to log additional finding: #{e.record.errors.full_messages.join(', ')}"
    end
  rescue => e
    Rails.logger.error "Error in create_additional_finding: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    
    if @job.present?
      redirect_to vmcott_mechanic_job_path(@job), alert: "An error occurred: #{e.message}"
    else
      redirect_to vmcott_mechanic_dashboard_path, alert: "An error occurred: #{e.message}"
    end
  end

  # =====================================================
  # TASK MANAGEMENT METHODS
  # =====================================================
  
  def tasks
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    @assigned_tasks = JobTask
      .where(assigned_mechanic_id: current_user.id)
      .where(status: ['approved', 'in_progress', 'paused', 'blocked'])
      .includes(inspection_job: { inspection: :vehicle })
      .order(priority: :desc, created_at: :asc)
    
    @available_tasks = JobTask
      .where(assigned_mechanic_id: nil)
      .where(status: 'approved')
      .includes(inspection_job: { inspection: :vehicle })
      .order(priority: :desc, created_at: :asc)
      .limit(20)
    
    @completed_tasks_count = JobTask
      .where(assigned_mechanic_id: current_user.id)
      .where(status: 'completed')
      .where('completed_at >= ?', Time.current.beginning_of_day)
      .count
    
    @in_progress_count = @assigned_tasks.where(status: 'in_progress').count
    @paused_count = @assigned_tasks.where(status: 'paused').count
    @blocked_count = @assigned_tasks.where(status: 'blocked').count
    
    @total_hours_today = WorkSession
      .where(mechanic_id: current_user.id)
      .where(session_type: 'work')
      .where('started_at >= ?', Time.current.beginning_of_day)
      .sum(:duration_hours)
    
    render :tasks
  end

  def task_show
    @task = JobTask.find(params[:id])
    
    unless @task.assigned_mechanic_id == current_user.id
      redirect_to vmcott_mechanic_tasks_path, alert: "Access denied - this task is not assigned to you"
      return
    end
    
    @work_sessions = @task.work_sessions.order(started_at: :desc)
    @active_session = @task.active_work_session
    @dependencies = @task.depends_on
    @inspection_job = @task.inspection_job
    
    # Safe navigation for work_order and vehicle
    @work_order = @inspection_job&.work_order if @inspection_job.present?
    
    # Safe navigation for dependent tasks if needed
    @dependent_tasks = []  # If you need this, you can calculate it or remove it
  end

  def task_start
    @task = JobTask.find(params[:id])
    
    unless @task.assigned_mechanic_id == current_user.id
      redirect_to vmcott_mechanic_tasks_path, alert: "Access denied"
      return
    end
    
    service = TaskExecutionService.new(@task, current_user)
    idempotency_key = generate_idempotency_key
    
    if service.start(idempotency_key)
      redirect_to vmcott_mechanic_task_path(@task), notice: "Task started successfully"
    else
      redirect_to vmcott_mechanic_tasks_path, alert: service.errors.join(", ")
    end
  end

  def task_pause
    @task = JobTask.find(params[:id])
    reason = params[:reason] || params[:task][:reason] if params[:task]
    
    service = TaskExecutionService.new(@task, current_user)
    idempotency_key = generate_idempotency_key
    
    if service.pause(reason, idempotency_key)
      redirect_to vmcott_mechanic_task_path(@task), notice: "Task paused"
    else
      redirect_to vmcott_mechanic_task_path(@task), alert: service.errors.join(", ")
    end
  end

  def task_resume
    @task = JobTask.find(params[:id])
    
    service = TaskExecutionService.new(@task, current_user)
    idempotency_key = generate_idempotency_key
    
    if service.resume(idempotency_key)
      redirect_to vmcott_mechanic_task_path(@task), notice: "Task resumed"
    else
      redirect_to vmcott_mechanic_task_path(@task), alert: service.errors.join(", ")
    end
  end

  def task_complete
    @task = JobTask.find(params[:id])
    
    service = TaskExecutionService.new(@task, current_user)
    idempotency_key = generate_idempotency_key
    
    if service.complete(idempotency_key)
      redirect_to vmcott_mechanic_tasks_path, notice: "Task completed!"
    else
      redirect_to vmcott_mechanic_task_path(@task), alert: service.errors.join(", ")
    end
  end

  def task_block
    @task = JobTask.find(params[:id])
    reason = params[:reason] || params[:task][:reason] if params[:task]
    
    service = TaskExecutionService.new(@task, current_user)
    idempotency_key = generate_idempotency_key
    
    if service.block(reason, idempotency_key)
      redirect_to vmcott_mechanic_task_path(@task), notice: "Task blocked. Supervisor notified."
    else
      redirect_to vmcott_mechanic_task_path(@task), alert: service.errors.join(", ")
    end
  end

  def task_add_finding
    @task = JobTask.find(params[:task_id] || params[:id])
    
    finding = @task.findings.build(
      work_order: @task.inspection_job.work_order,
      description: params[:description],
      severity: params[:severity] || 'normal',
      blocking: params[:blocking] == 'true',
      finding_type: 'mechanic',
      created_by: current_user
    )
    
    if finding.save
      if finding.blocking?
        service = TaskExecutionService.new(@task, current_user)
        service.block(finding.description, generate_idempotency_key)
      end
      redirect_to vmcott_mechanic_task_path(@task), notice: "Finding added successfully"
    else
      redirect_to vmcott_mechanic_task_path(@task), alert: finding.errors.full_messages.join(", ")
    end
  end

  private

  def require_mechanic
    unless current_user.mechanic? || current_user.maintenance_supervisor? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Mechanic privileges required."
    end
  end

  def set_job_context
    @job = InspectionJob.includes(inspection: :vehicle).find_by(id: params[:id])
    
    if @job.nil?
      flash[:alert] = "Job not found."
      redirect_to vmcott_mechanic_dashboard_path and return false
    end
    
    if @job.assigned_mechanic_id == current_user.id
      @assignment = MechanicAssignment.find_or_initialize_by(
        inspection_job_id: @job.id,
        mechanic_id: current_user.id
      )
      
      if @assignment.new_record?
        @assignment.status = 'assigned'
        @assignment.started_at = Time.current
        @assignment.save!
      end
    else
      @assignment = MechanicAssignment.find_by(
        inspection_job_id: @job.id,
        mechanic_id: @job.assigned_mechanic_id
      )
    end
    
    true
  end

  def ensure_can_start_job
    return unless @job
    
    # ✅ Allow starting from 'assigned' or 'approved_for_work'
    unless @job.status == 'assigned' || @job.status == 'approved_for_work'
      redirect_to vmcott_mechanic_job_path(@job), alert: "This job is not approved for work yet. Current status: #{@job.status}."
      return false
    end
    true
  end

  def ensure_can_request_parts
    return unless @job
    
    assignment = MechanicAssignment.find_by(inspection_job_id: @job.id, mechanic_id: current_user.id)
    unless assignment&.in_progress?
      flash[:alert] = "Parts can only be requested when job is in progress."
      redirect_to vmcott_mechanic_job_path(@job) and return false
    end
    true
  end

  def ensure_can_do_pre_check
    return unless @job
    
    unless @job.status == 'assigned'
      redirect_to vmcott_mechanic_job_path(@job), alert: "This job is not ready for pre-check."
      return false
    end
    true
  end

  def generate_idempotency_key
    "task_#{params[:id]}_#{Time.current.to_i}_#{SecureRandom.hex(4)}"
  end

  def notify_inventory_manager(inspection, part_name = nil, quantity = nil, is_custom = false)
    inventory_manager_ids = User.where(role: 'inventory_manager').pluck(:id)
    
    if inventory_manager_ids.any?
      if part_name
        title = "New Part Request"
        message = "Part: #{part_name} x#{quantity} requested for #{inspection.vehicle.license_plate}"
      else
        title = "Parts Need Review"
        message = "Inspection ##{inspection.id} for #{inspection.vehicle.license_plate} has parts pending review."
      end
      
      Notification.create!(
        title: title,
        message: message,
        link: "/vmcott/inventory_manager/dashboard",
        user_id: inventory_manager_ids,
        notifiable_type: 'Inspection',
        notifiable_id: inspection.id,
        notification_type: 'info'
      )
    end
  rescue => e
    Rails.logger.error "Failed to create notification: #{e.message}"
  end

  def notify_mechanics_work_ready(inspection)
    mechanic_ids = User.where(role: 'mechanic').pluck(:id)
    Notification.create!(
      title: "Work Ready",
      message: "Inspection ##{inspection.id} for #{inspection.vehicle.license_plate} is ready for work.",
      link: "/vmcott/mechanic/dashboard",
      user_id: mechanic_ids,
      notifiable_type: 'Inspection',
      notifiable_id: inspection.id,
      notification_type: 'success'
    )
  rescue => e
    Rails.logger.error "Failed to create notification: #{e.message}"
  end

  def notify_finance_for_additional_quotation(maintenance)
    finance_users = User.where(role: ['finance', 'admin']).pluck(:id)
    Notification.create!(
      title: "Additional Work Requires Quotation",
      message: "Additional work '#{maintenance.description}' needs a quotation for the agency.",
      link: "/vmcott/finance/quotations/new_for_maintenance/#{maintenance.id}",
      user_id: finance_users,
      notifiable_type: 'Maintenance',
      notifiable_id: maintenance.id,
      notification_type: 'warning'
    )
  rescue => e
    Rails.logger.error "Failed to create notification: #{e.message}"
  end

  def disable_caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end

  helper_method :job_status, :job_status_color, :waiting_status, :waiting_status_color

  def job_status(job, assignment = nil)
    if job.completed_at
      return "✅ Completed"
    end
    
    if assignment&.started_at
      return "🔧 In Progress"
    end
    
    case job.status
    when 'assigned'
      return "🔍 Pre-Check Required"
    when 'pre_check_in_progress'
      return "🔎 Pre-Check in Progress"
    when 'pre_check_completed'
      return "📋 Awaiting Approval"
    when 'approved_for_work'
      return "✅ Ready to Start"
    when 'in_progress'
      return "⚙️ In Progress"
    when 'paused'
      return "⏸️ Paused"
    when 'blocked'
      return "🚫 Blocked"
    else
      waiting_status(job)
    end
  end

  def job_status_color(job, assignment = nil)
    if job.completed_at
      return 'success'
    end
    
    if assignment&.started_at
      return 'warning'
    end
    
    case job.status
    when 'assigned'
      return 'info'
    when 'pre_check_in_progress'
      return 'primary'
    when 'pre_check_completed'
      return 'warning'
    when 'approved_for_work'
      return 'success'
    when 'in_progress'
      return 'info'
    when 'paused'
      return 'secondary'
    when 'blocked'
      return 'danger'
    else
      waiting_status_color(job)
    end
  end

  def waiting_status(job)
    if job.verification_status != 'approved'
      return "⏳ Waiting for inspector"
    end
    
    case job.inspection&.status
    when 'received'
      return "⏳ Waiting for inspection"
    when 'inspected'
      return "🔍 Diagnosis required"
    when 'diagnosed'
      return "📝 Jobs pending creation"
    when 'parts_pending'
      return "📦 Waiting for parts"
    when 'qc_pending'
      return "✅ Ready for QC"
    when 'ready_for_pickup'
      return "✅ Ready for pickup"
    when 'completed'
      return "✅ Already completed"
    else
      return "⏳ Waiting for approval"
    end
  end

  def waiting_status_color(job)
    if job.verification_status != 'approved'
      return 'warning'
    end
    
    case job.inspection&.status
    when 'received', 'inspected'
      return 'info'
    when 'diagnosed'
      return 'primary'
    when 'parts_pending'
      return 'warning'
    when 'qc_pending', 'ready_for_pickup'
      return 'success'
    else
      return 'secondary'
    end
  end
end also just a little insight after the parts are requested by the mechanic to the supervisor he just approve or rejects the request, then what parts are approve the inventory gets the request and the system tells inventory if the part exist, if it does then inventory will send back the approval to the supervisor if the part doesnt exist inventory sends it to procurement where they make request to get it and what not then when the part arrives they send it back to inventory where inventory  will send it to the supervisor, then i not sure who you tell me ( does the supervisor tell the client the job/parts prices and waits for a response or does procurement do that?) then after the jobs and parts prices are receive and whatever payment happen(weather pay online schedule appointment or whatever) then  the supervisor gives permission to the mechanic to start the job 