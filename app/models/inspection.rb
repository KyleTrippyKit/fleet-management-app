# app/models/inspection.rb
class Inspection < ApplicationRecord
  include Auditable
  
  belongs_to :vehicle
  belongs_to :inspector, class_name: 'User', optional: true
  belongs_to :supervisor, class_name: 'User', optional: true
  belongs_to :assigned_mechanic, class_name: 'User', optional: true
  belongs_to :work_order, optional: true
  belongs_to :purchase_order, optional: true
  belongs_to :final_inspector, class_name: 'User', optional: true
  belongs_to :workflow_selected_by, class_name: "User", foreign_key: "workflow_selected_by_id", optional: true
  
  has_many :inspection_jobs, dependent: :destroy
  has_many :parts_requests, dependent: :destroy
  has_many :quotations, dependent: :nullify
  has_many :findings, dependent: :destroy

  # =========================
  # SIMPLIFIED STATUS ENGINE (14-STEP WORKFLOW)
  # =========================
  enum :status, {
    received: "received",
    inspected: "inspected",
    diagnosed: "diagnosed",
    jobs_created: "jobs_created",
    parts_pending: "parts_pending",
    parts_ready: "parts_ready",
    awaiting_approval: "awaiting_approval",
    approved: "approved",
    in_progress: "in_progress",
    qc_pending: "qc_pending",
    additional_findings_pending: "additional_findings_pending",
    on_hold: "on_hold",
    ready_for_pickup: "ready_for_pickup",
    completed: "completed",
    cancelled: "cancelled"
  }

  # Workflow tracking fields
  attribute :workflow_type, :string, default: 'work_before_payment'
  attribute :client_approval_status, :string, default: 'pending'
  attribute :client_selected_jobs, :jsonb, default: {}
  attribute :payment_status, :string, default: 'pending'
  attribute :scope_locked, :boolean, default: false
  attribute :labor_rate, :decimal, precision: 10, scale: 2
  attribute :parts_markup_percentage, :integer, default: 30
  attribute :diagnosis_notes, :text
  attribute :diagnosis_completed_at, :datetime  # ✅ This column exists in DB
  attribute :qc_passed_at, :datetime
  attribute :qc_inspector_id, :integer
  attribute :qc_notes, :text
  attribute :rework_required, :boolean, default: false
  attribute :rework_reason, :text
  attribute :started_at, :datetime
  attribute :completed_at, :datetime
  attribute :ready_for_pickup_at, :datetime
  attribute :pickup_code, :string
  attribute :pickup_scheduled_at, :datetime
  attribute :actual_pickup_date, :datetime
  attribute :picked_up_by, :string
  attribute :cancelled_at, :datetime
  attribute :cancellation_reason, :text
  attribute :mileage_at_inspection, :integer
  attribute :notes, :text

  validates :status, presence: true
  validates :diagnosis_notes, presence: true, if: -> { diagnosed? && diagnosis_completed_at.present? }

  # =========================
  # WORKFLOW RULES (SAFETY GUARDS)
  # =========================

  def parts_ready?
    parts_requests.all? { |p| p.approved? && p.available? }
  end

  def can_create_quote?
    jobs_created? && parts_ready?
  end

  def quote_approved?
    quotations.where(status: "approved").exists?
  end

  def scope_locked?
    scope_locked || approved? || in_progress? || qc_pending? || ready_for_pickup? || completed?
  end

  def all_jobs_completed?
    inspection_jobs.where(status: 'completed').count == inspection_jobs.count
  end

  # =========================
  # SAFE TRANSITIONS (WITH GUARDS)
  # =========================

  def move_to_inspected!
    return false unless received?
    update!(status: :inspected)
    notify_mechanics_for_diagnosis
    true
  end

  def move_to_diagnosed!
    return false unless inspected?
    update!(status: :diagnosed, diagnosis_completed_at: Time.current)
    notify_supervisor_for_job_creation
    true
  end

  def move_to_jobs_created!
    return false unless diagnosed?
    update!(status: :jobs_created)
    true
  end

  def move_to_parts_pending!
    return false unless jobs_created?
    update!(status: :parts_pending)
    true
  end

  def move_to_parts_ready!
    return false unless parts_pending? && parts_ready?
    update!(status: :parts_ready)
    true
  end

  def move_to_awaiting_approval!
    return false unless parts_ready?
    update!(status: :awaiting_approval)
    notify_customer_for_approval
    true
  end

  def move_to_approved!
    return false unless awaiting_approval?
    update!(status: :approved, scope_locked: true)
    notify_mechanics_work_ready
    true
  end

  def move_to_in_progress!
    return false unless approved?
    update!(status: :in_progress, started_at: Time.current)
    true
  end

  def move_to_qc_pending!
    return false unless in_progress? && all_jobs_completed?
    update!(status: :qc_pending)
    notify_qc_inspector
    true
  end

  def move_to_ready_for_pickup!
    return false unless qc_pending?
    update!(status: :ready_for_pickup, ready_for_pickup_at: Time.current, pickup_code: generate_pickup_code)
    notify_customer_ready
    notify_billing_for_invoice
    true
  end

  def move_to_completed!
    return false unless ready_for_pickup?
    update!(status: :completed, completed_at: Time.current)
    notify_supervisor_completion
    true
  end

  def pause!(reason)
    return false unless in_progress?
    update!(status: :on_hold, hold_reason: reason, paused_at: Time.current)
    true
  end

  def resume!
    return false unless on_hold?
    update!(status: :in_progress, hold_reason: nil, paused_at: nil)
    true
  end

  def cancel!(reason)
    return false if completed?
    update!(status: :cancelled, cancellation_reason: reason, cancelled_at: Time.current)
    true
  end

  # =========================
  # NOTIFICATION HELPERS
  # =========================

  def notify_mechanics_for_diagnosis
    mechanic_ids = User.where(role: 'mechanic').pluck(:id)
    Notification.create!(
      user_id: mechanic_ids,
      title: "🔧 Diagnosis Required",
      message: "Vehicle #{vehicle.license_plate} needs diagnosis",
      link: "/vmcott/mechanic/diagnosis/#{id}",
      notifiable: self,
      notification_type: 'info'
    )
  rescue => e
    Rails.logger.error "Failed to notify mechanics: #{e.message}"
  end

  def notify_supervisor_for_job_creation
    supervisor_ids = User.where(role: 'workshop_supervisor').pluck(:id)
    Notification.create!(
      user_id: supervisor_ids,
      title: "📋 Job Creation Required",
      message: "Diagnosis complete for #{vehicle.license_plate}",
      link: "/vmcott/workshop_supervisor/inspections/#{id}/job_creation",
      notifiable: self,
      notification_type: 'info'
    )
  rescue => e
    Rails.logger.error "Failed to notify supervisor: #{e.message}"
  end

  def notify_customer_for_approval
    Rails.logger.info "Notify customer for approval for inspection #{id}"
  end

  def notify_mechanics_work_ready
    if assigned_mechanic_id.present?
      Notification.create!(
        user_id: assigned_mechanic_id,
        title: "🚨 Work Ready",
        message: "Work approved for #{vehicle.license_plate}",
        link: "/vmcott/mechanic/jobs",
        notifiable: self,
        notification_type: 'success'
      )
    end
  rescue => e
    Rails.logger.error "Failed to notify mechanic: #{e.message}"
  end

  def notify_qc_inspector
    inspector_ids = User.where(role: 'inspector').pluck(:id)
    Notification.create!(
      user_id: inspector_ids,
      title: "✅ QC Required",
      message: "Work completed for #{vehicle.license_plate}",
      link: "/vmcott/inspector/qc/#{id}",
      notifiable: self,
      notification_type: 'info'
    )
  rescue => e
    Rails.logger.error "Failed to notify QC inspector: #{e.message}"
  end

  def notify_customer_ready
    Rails.logger.info "Notify customer vehicle is ready for pickup"
  end

  def notify_billing_for_invoice
    billing_ids = User.where(role: ['procurement', 'finance']).pluck(:id)
    Notification.create!(
      user_id: billing_ids,
      title: "💰 Invoice Required",
      message: "Vehicle #{vehicle.license_plate} passed QC",
      link: "/vmcott/finance/invoices/new?inspection_id=#{id}",
      notifiable: self,
      notification_type: 'info'
    )
  rescue => e
    Rails.logger.error "Failed to notify billing: #{e.message}"
  end

  def notify_supervisor_completion
    supervisor_ids = User.where(role: 'workshop_supervisor').pluck(:id)
    Notification.create!(
      user_id: supervisor_ids,
      title: "✅ Vehicle Completed",
      message: "#{vehicle.license_plate} has been completed",
      link: "/vmcott/workshop_supervisor/inspections/#{id}",
      notifiable: self,
      notification_type: 'success'
    )
  rescue => e
    Rails.logger.error "Failed to notify supervisor: #{e.message}"
  end

  # =========================
  # COST CALCULATION
  # =========================

  def total_labor_cost
    inspection_jobs.sum(:estimated_labor_cost).to_f
  end

  def total_parts_cost
    parts_requests.where(status: 'approved').sum(:customer_price).to_f
  end

  def total_estimated_cost
    total_labor_cost + total_parts_cost
  end

  def latest_quotation
    quotations.order(created_at: :desc).first
  end

  # =========================
  # HELPER METHODS
  # =========================

  def can_transition_to?(new_status)
    workflow_transitions = {
      received: [:inspected, :cancelled],
      inspected: [:diagnosed, :cancelled],
      diagnosed: [:jobs_created, :cancelled],
      jobs_created: [:parts_pending, :cancelled],
      parts_pending: [:parts_ready, :cancelled],
      parts_ready: [:awaiting_approval, :cancelled],
      awaiting_approval: [:approved, :cancelled],
      approved: [:in_progress, :cancelled],
      in_progress: [:qc_pending, :additional_findings_pending, :on_hold, :cancelled],
      additional_findings_pending: [:in_progress, :cancelled],
      qc_pending: [:ready_for_pickup, :cancelled],
      ready_for_pickup: [:completed, :on_hold, :cancelled],
      on_hold: [:in_progress, :cancelled],
      completed: [],
      cancelled: []
    }
    workflow_transitions[status.to_sym]&.include?(new_status.to_sym) || false
  end

  def transition_to!(new_status, reason = nil)
    unless can_transition_to?(new_status)
      raise "Invalid transition from #{status} to #{new_status}"
    end
    
    send("move_to_#{new_status}!".to_sym)
  end

  def timeline_events
    events = []
    events << { date: created_at, title: "Vehicle Received", description: "Work order created" }
    events << { date: started_at, title: "Work Started", description: "Repair work began" } if started_at
    events << { date: ready_for_pickup_at, title: "Ready for Pickup", description: "Vehicle ready" } if ready_for_pickup_at
    events << { date: completed_at, title: "Completed", description: "Vehicle picked up" } if completed_at
    events.sort_by { |e| e[:date] || Time.current }
  end

  private

  def generate_pickup_code
    "PK-#{id}-#{SecureRandom.hex(4).upcase}"
  end
end