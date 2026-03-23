# app/models/inspection.rb
class Inspection < ApplicationRecord
  belongs_to :vehicle
  belongs_to :inspector, class_name: 'User'
  belongs_to :purchase_order, optional: true
  belongs_to :final_inspector, class_name: 'User', optional: true

  has_many :inspection_jobs, dependent: :destroy
  has_many :parts_requests, dependent: :destroy
  has_many :quotations, dependent: :nullify  # <-- ADDED: Link to quotations

  # Status workflow - added pending_mechanic_review
  enum :status, {
    pending_inspection: 'pending_inspection',
    inspection_completed: 'inspection_completed',
    pending_mechanic_review: 'pending_mechanic_review',
    parts_coordinator_review: 'parts_coordinator_review',
    billing_review: 'billing_review',
    awaiting_customer_approval_original: 'awaiting_customer_approval_original',
    awaiting_customer_approval_additional: 'awaiting_customer_approval_additional',
    approved_for_repair: 'approved_for_repair',
    in_progress: 'in_progress',
    ready_for_qc: 'ready_for_qc',
    qc_completed: 'qc_completed',
    ready_for_pickup: 'ready_for_pickup',
    completed: 'completed',
    cancelled_by_agency: 'cancelled_by_agency'
  }, default: :pending_inspection, validate: true

  validates :status, presence: true
  validates :mileage_at_inspection, numericality: { greater_than: 0 }, allow_nil: true

  # Scopes for notifications - updated
  scope :needing_mechanic_review, -> { where(status: :pending_mechanic_review) }
  scope :needing_parts_coordinator, -> { where(status: :parts_coordinator_review) }
  scope :needing_billing_review, -> { where(status: :billing_review) }
  scope :needing_mechanic_notification, -> { where(status: :approved_for_repair) }
  scope :ready_for_final_qc, -> { where(status: :ready_for_qc) }
  scope :ready_for_pickup, -> { where(status: :ready_for_pickup) }

  # 🔥 NEW: Parts used by mechanics (from parts_requests that have been received/used)
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

  # After inspection is completed, notify parts coordinator if any parts are needed
  after_update :notify_parts_coordinator_if_needed, if: :saved_change_to_status?

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

  # 🔥 NEW: Get the latest quotation for this inspection
  def latest_quotation
    quotations.order(created_at: :desc).first
  end

  # 🔥 NEW: Check if customer has approved the quotation
  def customer_approved?
    quotations.exists?(status: ['approved', 'partially_approved'])
  end

  # 🔥 NEW: Check if customer approval is pending
  def customer_approval_pending?
    quotations.exists?(status: ['sent', 'pending_approval'])
  end

  # 🔥 NEW: Get the quotation that needs customer approval
  def pending_quotation
    quotations.where(status: ['sent', 'pending_approval']).order(created_at: :desc).first
  end

  private

  def notify_parts_coordinator_if_needed
    if status == 'parts_coordinator_review' && parts_requests.any?
      notify_parts_coordinator!
    end
  end
end