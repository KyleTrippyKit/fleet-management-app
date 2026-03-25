# app/models/inspection.rb
class Inspection < ApplicationRecord
  include Auditable
  
  belongs_to :vehicle
  has_many :reception_logs, through: :vehicle
  belongs_to :inspector, class_name: 'User'
  belongs_to :supervisor, class_name: 'User', optional: true  # NEW
  belongs_to :purchase_order, optional: true
  belongs_to :final_inspector, class_name: 'User', optional: true

  has_many :inspection_jobs, dependent: :destroy
  has_many :parts_requests, dependent: :destroy
  has_many :quotations, dependent: :nullify
  has_many :findings, dependent: :destroy

  # Status workflow - expanded with new statuses
  enum :status, {
    pending_inspection: 'pending_inspection',
    inspection_completed: 'inspection_completed',
    pending_supervisor_review: 'pending_supervisor_review',  # NEW - after inspection
    pending_mechanic_review: 'pending_mechanic_review',
    parts_coordinator_review: 'parts_coordinator_review',
    pending_procurement_quotation: 'pending_procurement_quotation',
    awaiting_client_approval: 'awaiting_client_approval',
    billing_review: 'billing_review',
    awaiting_customer_approval_original: 'awaiting_customer_approval_original',
    awaiting_customer_approval_additional: 'awaiting_customer_approval_additional',
    approved_for_repair: 'approved_for_repair',
    in_progress: 'in_progress',
    paused: 'paused',
    blocked: 'blocked',
    rework_needed: 'rework_needed',
    ready_for_qc: 'ready_for_qc',
    qc_completed: 'qc_completed',
    ready_for_pickup: 'ready_for_pickup',
    completed: 'completed',
    cancelled_by_agency: 'cancelled_by_agency',
    on_hold: 'on_hold'
  }, default: :pending_inspection, validate: true

  # Add new fields for workflow
  attribute :workflow_type, :string, default: 'work_before_payment'
  attribute :client_approval_status, :string, default: 'pending'
  attribute :client_selected_jobs, :jsonb, default: {}
  attribute :payment_status, :string, default: 'pending'
  attribute :pickup_code, :string
  attribute :pickup_scheduled_at, :datetime
  attribute :storage_fee_days, :integer, default: 0
  attribute :client_type, :string
  attribute :payment_terms, :string
  attribute :rejection_reason, :text
  attribute :hold_reason, :text
  attribute :paused_at, :datetime
  attribute :paused_reason, :text
  attribute :blocked_at, :datetime
  attribute :blocked_reason, :text
  attribute :qc_failed_at, :datetime
  attribute :qc_failure_reason, :text
  attribute :rework_completed_at, :datetime
  attribute :customer_signature, :string
  attribute :intake_photos, :jsonb, default: []
  attribute :final_photos, :jsonb, default: []
  attribute :expected_pickup_date, :date
  attribute :actual_pickup_date, :datetime
  attribute :picked_up_by, :string
  attribute :ready_for_pickup_at, :datetime
  attribute :parts_coordinator_notified_at, :datetime
  attribute :mechanic_notified_at, :datetime
  attribute :billing_notified_at, :datetime
  attribute :tax_rate, :decimal, default: 0
  attribute :discount_percentage, :decimal, default: 0

  validates :status, presence: true
  validates :mileage_at_inspection, numericality: { greater_than: 0 }, allow_nil: true

  # Scopes for new statuses
  scope :needing_supervisor_review, -> { where(status: :pending_supervisor_review) }
  scope :needing_mechanic_review, -> { where(status: :pending_mechanic_review) }
  scope :needing_parts_coordinator, -> { where(status: :parts_coordinator_review) }
  scope :needing_billing_review, -> { where(status: :billing_review) }
  scope :needing_procurement_quotation, -> { where(status: :pending_procurement_quotation) }
  scope :awaiting_client, -> { where(status: :awaiting_client_approval) }
  scope :blocked_jobs, -> { where(status: :blocked) }
  scope :paused_jobs, -> { where(status: :paused) }
  scope :on_hold, -> { where(status: :on_hold) }
  scope :ready_for_work, -> { where(status: :approved_for_repair).where(payment_status: 'paid') }
  scope :needing_mechanic_notification, -> { where(status: :approved_for_repair) }
  scope :ready_for_final_qc, -> { where(status: :ready_for_qc) }
  scope :ready_for_pickup, -> { where(status: :ready_for_pickup) }
  scope :overdue_pickup, -> { ready_for_pickup.where('ready_for_pickup_at < ?', 3.days.ago) }

  # Parts used by mechanics
  def parts_used_by_mechanics
    parts_requests.where(status: ['parts_received', 'used', 'installed', 'completed'])
  end

  def total_parts_used
    parts_used_by_mechanics.sum(:quantity)
  end

  def parts_used_list
    parts_used_by_mechanics.map { |pr| pr.part&.name || pr.custom_part_name }.compact.uniq
  end

  def parts_used_display
    total = total_parts_used
    return "No parts used" if total == 0

    list = parts_used_list
    if list.size <= 3
      "#{total} part(s): #{list.join(', ')}"
    else
      "#{total} part(s): #{list.first(3).join(', ')} + #{list.size - 3} more"
    end
  end

  after_update :notify_parts_coordinator_if_needed, if: :saved_change_to_status?

  # Helper methods for new workflow
  def client_can_start_work?
    return false unless client_approval_status == 'full_approved' || client_approval_status == 'partial_approved'
    
    if workflow_type == 'payment_before_work'
      payment_status == 'paid'
    else
      true
    end
  end

  def needs_payment_before_work?
    workflow_type == 'payment_before_work' && payment_status != 'paid'
  end

  def approved_job_ids
    return [] if client_selected_jobs.blank?
    client_selected_jobs.map(&:to_i)
  end

  def job_approved?(job_id)
    approved_job_ids.include?(job_id.to_s) || approved_job_ids.include?(job_id)
  end

  def total_approved_jobs_cost
    inspection_jobs.where(id: approved_job_ids).sum(&:estimated_total)
  end

  def has_unapproved_work?
    inspection_jobs.where.not(id: approved_job_ids).exists?
  end

  def total_estimated_cost
    inspection_jobs.sum(&:estimated_total)
  end

  def all_parts_available?
    parts_requests.where(status: ['pending', 'ordered']).none?
  end

  def has_jobs?
    inspection_jobs.any?
  end

  def has_parts?
    parts_requests.any?
  end

  def parts_need_ordering?
    parts_requests.where(in_stock: false).any?
  end

  def inspection_only?
    !has_jobs? && !has_parts?
  end

  def needs_parts_coordinator?
    has_parts? && parts_need_ordering?
  end

  def can_go_directly_to_workshop?
    has_jobs? && (!has_parts? || !parts_need_ordering?)
  end

  def pause!(reason)
    update!(
      status: :paused,
      paused_at: Time.current,
      paused_reason: reason
    )
  end

  def block!(reason)
    update!(
      status: :blocked,
      blocked_at: Time.current,
      blocked_reason: reason
    )
  end

  def unblock!
    update!(
      status: :pending_mechanic_review,
      blocked_at: nil,
      blocked_reason: nil
    )
  end

  def require_rework!(reason)
    update!(
      status: :rework_needed,
      qc_failed_at: Time.current,
      qc_failure_reason: reason
    )
  end

  def mark_ready_for_pickup!
    update!(
      status: :ready_for_pickup,
      ready_for_pickup_at: Time.current,
      pickup_code: generate_pickup_code
    )
  end

  def record_pickup!(picked_by)
    update!(
      status: :completed,
      actual_pickup_date: Time.current,
      picked_up_by: picked_by
    )
    
    if expected_pickup_date && Time.current.to_date > expected_pickup_date
      days_late = (Time.current.to_date - expected_pickup_date).to_i
      update!(storage_fee_days: days_late)
      create_storage_fee_invoice(days_late)
    end
  end

  def total_storage_fee
    return 0 unless storage_fee_days > 0
    daily_rate = 50.00
    storage_fee_days * daily_rate
  end

  def check_parts_availability!
    if all_parts_available?
      update(status: 'approved_for_repair')
      notify_mechanics!
    end
  end

  def notify_parts_coordinator!
    update(parts_coordinator_notified_at: Time.current)
    if defined?(PartsCoordinatorNotificationJob)
      PartsCoordinatorNotificationJob.perform_later(id)
    else
      Rails.logger.info "Would notify parts coordinator for inspection #{id}"
    end
  end

  def notify_mechanics!
    update(mechanic_notified_at: Time.current)
    if defined?(MechanicNotificationJob)
      MechanicNotificationJob.perform_later(id)
    else
      Rails.logger.info "Would notify mechanics for inspection #{id}"
    end
  end

  def notify_billing_team!
    update(billing_notified_at: Time.current)
    if defined?(BillingNotificationJob)
      BillingNotificationJob.perform_later(id)
    else
      Rails.logger.info "Would notify billing team for inspection #{id}"
    end
  end

  def notify_receptionist_for_pickup!
    Rails.logger.info "Would notify receptionist that vehicle #{vehicle.license_plate} is ready for pickup"
  end

  def latest_quotation
    quotations.order(created_at: :desc).first
  end

  def customer_approved?
    quotations.exists?(status: ['approved', 'partially_approved'])
  end

  def customer_approval_pending?
    quotations.exists?(status: ['sent', 'pending_approval'])
  end

  def pending_quotation
    quotations.where(status: ['sent', 'pending_approval']).order(created_at: :desc).first
  end

  private

  def generate_pickup_code
    "PK-#{id}-#{SecureRandom.hex(4).upcase}"
  end

  def create_storage_fee_invoice(days)
    return unless days > 0
    
    daily_rate = 50.00
    storage_fee = days * daily_rate
    
    if defined?(Invoice)
      Invoice.create!(
        inspection_id: self.id,
        vehicle: vehicle,
        amount: storage_fee,
        due_date: Time.current.to_date,
        status: 'pending',
        invoice_number: "STRG-#{self.id}-#{Time.current.strftime('%Y%m%d')}",
        invoice_date: Date.current,
        vendor: vehicle&.agency&.name || 'VMCOTT'
      )
    else
      Rails.logger.info "Would create storage fee invoice for #{storage_fee}"
    end
  end

  def notify_parts_coordinator_if_needed
    if status == 'parts_coordinator_review' && parts_requests.any?
      notify_parts_coordinator!
    end
  end
end