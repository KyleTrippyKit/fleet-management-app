# frozen_string_literal: true

class Rfq < ApplicationRecord
  # Associations
  belongs_to :requesting_agency, class_name: "Agency"
  belongs_to :processing_agency, class_name: "Agency", optional: true
  belongs_to :vehicle, optional: true
  belongs_to :maintenance_request, optional: true

  belongs_to :converted_to_quotation,
             class_name: "Quotation",
             foreign_key: "converted_to_quotation_id",
             optional: true

  has_many :rfq_line_items, dependent: :destroy
  accepts_nested_attributes_for :rfq_line_items, allow_destroy: true, reject_if: :all_blank

  # Validations
  validates :rfq_number, presence: true, uniqueness: true
  validates :request_date, presence: true
  validates :requesting_agency_id, presence: true

  # Enum (string-backed)
  enum :status, {
    draft: "draft",
    submitted: "submitted",
    under_review: "under_review",
    quoted: "quoted",
    converted: "converted",
    rejected: "rejected",
    accepted: "accepted"
  }, default: :draft

  # Callbacks
  before_validation :generate_rfq_number, on: :create

  after_create :send_creation_notification
  after_update :send_status_notification, if: :saved_change_to_status?

  def submit_to_vmcott!
    update(status: "submitted")
  end

  # UI helpers
  def status_badge_color
    case status
    when "draft"       then "secondary"
    when "submitted"   then "info"
    when "under_review" then "warning"
    when "quoted"      then "primary"
    when "converted"   then "success"
    when "accepted"    then "success"
    when "rejected"    then "danger"
    else "secondary"
    end
  end

  def pdf_filename
    "#{rfq_number.to_s.gsub(/[^a-zA-Z0-9]/, "_")}.pdf"
  end

  def total_items
    rfq_line_items.sum(:quantity)
  end

  def response_overdue?
    return false if response_due_date.blank?
    response_due_date < Date.current && %w[submitted under_review].include?(status)
  end

  private

  def generate_rfq_number
    return if rfq_number.present?

    date_part = Time.current.strftime("%Y%m%d")
    random_part = SecureRandom.hex(3).upcase
    self.rfq_number = "RFQ-#{date_part}-#{random_part}"
  end

  def send_status_notification
    return unless defined?(RfqMailer)

    # skip “draft -> draft”
    old_status = status_before_last_save.to_s
    new_status = status.to_s
    return if old_status == "draft" && new_status == "draft"

    RfqMailer.status_changed(self).deliver_later
  rescue StandardError => e
    Rails.logger.error("RFQ status mail failed: #{e.class} - #{e.message}")
  end

  def send_creation_notification
    return unless defined?(RfqMailer)

    # Only send if created as submitted/under_review/etc (not drafts)
    return if draft?

    RfqMailer.rfq_created(self).deliver_later
  rescue StandardError => e
    Rails.logger.error("RFQ creation mail failed: #{e.class} - #{e.message}")
  end
end
