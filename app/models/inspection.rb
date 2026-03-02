# app/models/inspection.rb
class Inspection < ApplicationRecord
  belongs_to :vehicle
  belongs_to :inspector, class_name: 'User'
  belongs_to :purchase_order, optional: true
  belongs_to :final_inspector, class_name: 'User', optional: true

  has_many :inspection_jobs, dependent: :destroy
  has_many :parts_requests, dependent: :destroy

  # Status workflow - added pending_mechanic_review
  enum :status, {
    pending_inspection: 'pending_inspection',
    inspection_completed: 'inspection_completed',
    pending_mechanic_review: 'pending_mechanic_review',  # NEW: Waiting for mechanic to review
    parts_coordinator_review: 'parts_coordinator_review',
    billing_review: 'billing_review',
    awaiting_customer_approval: 'awaiting_customer_approval',
    approved_for_repair: 'approved_for_repair',
    in_progress: 'in_progress',
    ready_for_qc: 'ready_for_qc',
    qc_completed: 'qc_completed',
    ready_for_pickup: 'ready_for_pickup',
    completed: 'completed'
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

  # After inspection is completed, notify parts coordinator if any parts are needed
  after_update :notify_parts_coordinator_if_needed, if: :saved_change_to_status?

  def total_estimated_cost
    inspection_jobs.sum(&:estimated_total)  # now sums only labor, parts are separate
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

  private

  def notify_parts_coordinator_if_needed
    if status == 'parts_coordinator_review' && parts_requests.any?
      notify_parts_coordinator!
    end
  end
end