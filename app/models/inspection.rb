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
  
  # 🔥 NEW: Direct association to reception log (optional)
  belongs_to :reception_log, optional: true
  
  has_many :inspection_jobs, dependent: :destroy
  has_many :parts_requests, dependent: :destroy
  has_many :quotations, dependent: :nullify
  has_many :findings, dependent: :destroy
  has_many :inspection_recommendations, dependent: :destroy
  has_many :jobs, dependent: :destroy
  accepts_nested_attributes_for :inspection_jobs, allow_destroy: true, reject_if: :all_blank

  # Callbacks
  before_validation :assign_reception_log, on: :create

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
    parts_confirmed: "parts_confirmed",  # 🔥 NEW: Parts confirmed, ready for quotation
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
  attribute :diagnosis_completed_at, :datetime
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

  # Validations
  validates :status, presence: true
  validate :diagnosis_requirements

  def diagnosis_requirements
    return unless diagnosed?

    errors.add(:diagnosis_notes, "must be present") if diagnosis_notes.blank?
  end

  # =========================
  # 🔥 CALLBACK: AUTO-ASSIGN RECEPTION LOG
  # =========================
  def assign_reception_log
    return if reception_log.present? || vehicle.blank?

    self.reception_log = vehicle.reception_logs.order(created_at: :desc).first
  end
  
  # =========================
  # 🔥 CUSTOMER CONTACT HELPER
  # =========================
  def customer_contact_info
    log = reception_log
    return nil unless log
    {
      email: log.customer_email,
      name: log.customer_name
    }
  end

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
  # 🔥 PARTS AVAILABILITY METHODS
  # =========================
  
  def all_parts_available?
    pending_parts = parts_requests.where(status: ['needs_order', 'ordered'])
    pending_parts.empty?
  end
  
  def parts_pending?
    parts_requests.where(status: ['needs_order', 'ordered']).exists?
  end
  
  def pending_parts_count
    parts_requests.where(status: ['needs_order', 'ordered']).count
  end

  # =========================
  # 🔥 NEW: PARTS CONFIRMATION METHODS
  # =========================
  
  def all_parts_confirmed?
    parts_requests.where.not(status: 'confirmed').none?
  end
  
  def pending_confirmation_count
    parts_requests.where(status: ['approved', 'received']).count
  end
  
  def check_parts_confirmation!
    all_requests = parts_requests
    
    if all_requests.any? && all_requests.all? { |pr| pr.confirmed? }
      update!(status: 'parts_confirmed')
      
      supervisor_ids = User.where(role: 'workshop_supervisor').pluck(:id)
      if supervisor_ids.any?
        Notification.create!(
          user_id: supervisor_ids,
          title: "📋 All Parts Confirmed",
          message: "All parts for #{vehicle.license_plate} are CONFIRMED. Ready to create quotation.",
          link: "/vmcott/workshop_supervisor/quotations/new?inspection_id=#{id}",
          notification_type: 'success',
          notifiable: self
        )
      end
      Rails.logger.info "✅ Inspection ##{id} updated to parts_confirmed"
      true
    else
      false
    end
  end

  def can_create_quotation?
    status == 'parts_confirmed'
  end

  # =========================
  # PARTS USAGE METHODS
  # =========================

  def total_parts_used
    parts_requests.where(status: ['approved', 'received', 'confirmed']).sum(:quantity).to_i
  end

  def parts_used_list
    parts_requests.where(status: ['approved', 'received', 'confirmed']).map do |pr|
      pr.part&.name || pr.custom_part_name || "Unknown Part"
    end.uniq
  end

  def parts_used_display
    parts_used_list.first(3).join(', ') + (parts_used_list.size > 3 ? " + #{parts_used_list.size - 3} more" : "")
  end

  def total_parts_used_count
    total_parts_used
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
    return false unless has_recommendations?
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

  def move_to_parts_confirmed!
    return false unless parts_ready? && all_parts_confirmed?
    update!(status: :parts_confirmed)
    true
  end

  def move_to_awaiting_approval!
    return false unless parts_confirmed?
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
    update!(
      status: :ready_for_pickup, 
      ready_for_pickup_at: Time.current, 
      pickup_code: generate_pickup_code
    )
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
    mechanics = User.where(role: 'mechanic')
    mechanics.find_each do |mechanic|
      Notification.create!(
        user: mechanic,
        title: "🔧 Diagnosis Required",
        message: "Vehicle #{vehicle.license_plate} needs diagnosis",
        link: "/vmcott/mechanic/diagnosis/#{id}",
        notifiable: self,
        notification_type: 'info'
      )
    end
  rescue => e
    Rails.logger.error "Failed to notify mechanics: #{e.message}"
  end

  def notify_supervisor_for_job_creation
    supervisors = User.where(role: 'workshop_supervisor')
    supervisors.find_each do |supervisor|
      Notification.create!(
        user: supervisor,
        title: "📋 Job Creation Required",
        message: "Diagnosis complete for #{vehicle.license_plate}",
        link: "/vmcott/workshop_supervisor/inspections/#{id}/job_creation",
        notifiable: self,
        notification_type: 'info'
      )
    end
  rescue => e
    Rails.logger.error "Failed to notify supervisor: #{e.message}"
  end

  def notify_customer_for_approval
    Rails.logger.info "Notify customer for approval for inspection #{id}"
  end

  def notify_mechanics_work_ready
    if assigned_mechanic_id.present?
      mechanic = User.find_by(id: assigned_mechanic_id)
      if mechanic
        Notification.create!(
          user: mechanic,
          title: "🚨 Work Ready",
          message: "Work approved for #{vehicle.license_plate}",
          link: "/vmcott/mechanic/jobs",
          notifiable: self,
          notification_type: 'success'
        )
      end
    end
  rescue => e
    Rails.logger.error "Failed to notify mechanic: #{e.message}"
  end

  def notify_qc_inspector
    inspectors = User.where(role: 'inspector')
    inspectors.find_each do |inspector|
      Notification.create!(
        user: inspector,
        title: "✅ QC Required",
        message: "Work completed for #{vehicle.license_plate}",
        link: "/vmcott/inspector/qc/#{id}",
        notifiable: self,
        notification_type: 'info'
      )
    end
  rescue => e
    Rails.logger.error "Failed to notify QC inspector: #{e.message}"
  end

  def notify_customer_ready
    contact = customer_contact_info
    if contact&.dig(:email).present?
      CustomerMailer.vehicle_ready(
        self,
        contact[:email],
        contact[:name]
      ).deliver_later
      Rails.logger.info "✅ Email sent to #{contact[:email]} for inspection #{id}"
    else
      Rails.logger.warn "⚠️ No customer email found for inspection #{id}"
    end
  rescue => e
    Rails.logger.error "❌ Failed to send customer email: #{e.message}"
  end

  def notify_billing_for_invoice
    billing_users = User.where(role: ['procurement', 'finance'])
    billing_users.find_each do |user|
      Notification.create!(
        user: user,
        title: "💰 Invoice Required",
        message: "Vehicle #{vehicle.license_plate} passed QC",
        link: "/vmcott/finance/invoices/new?inspection_id=#{id}",
        notifiable: self,
        notification_type: 'info'
      )
    end
  rescue => e
    Rails.logger.error "Failed to notify billing: #{e.message}"
  end

  def notify_supervisor_completion
    supervisors = User.where(role: 'workshop_supervisor')
    supervisors.find_each do |supervisor|
      Notification.create!(
        user: supervisor,
        title: "✅ Vehicle Completed",
        message: "#{vehicle.license_plate} has been completed",
        link: "/vmcott/workshop_supervisor/inspections/#{id}",
        notifiable: self,
        notification_type: 'success'
      )
    end
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
    parts_requests.where(status: 'confirmed').sum(:customer_price).to_f
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

  def has_recommendations?
    inspection_recommendations.exists?
  end

  def can_transition_to?(new_status)
    workflow_transitions = {
      received: [:inspected, :cancelled],
      inspected: [:diagnosed, :cancelled],
      diagnosed: [:jobs_created, :cancelled],
      jobs_created: [:parts_pending, :cancelled],
      parts_pending: [:parts_ready, :cancelled],
      parts_ready: [:parts_confirmed, :cancelled],
      parts_confirmed: [:awaiting_approval, :cancelled],
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

  def all_parts_received?
    parts_requests.where.not(status: 'received').none?
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