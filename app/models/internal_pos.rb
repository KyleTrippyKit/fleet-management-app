# app/models/internal_pos.rb
class InternalPos < ApplicationRecord
  belongs_to :purchase_order, optional: true
  belongs_to :created_by, class_name: 'User'

  # NOTE:
  # We are intentionally NOT using vehicle_id / assigned_to_id anymore.
  # Vehicle is derived from purchase_order.vehicle for consistency and to avoid wrong values.

  enum :status, {
    pending: 'pending',
    in_progress: 'in_progress',
    completed: 'completed',
    cancelled: 'cancelled'
  }

  enum :priority, {
    low: 'low',
    normal: 'normal',
    high: 'high',
    urgent: 'urgent'
  }

  # -------------------------
  # Virtual fields for DEMO (no migration needed)
  # These values will be embedded into notes.
  # -------------------------
  attr_accessor :work_section, :work_role

  WORK_SECTIONS = [
    'Workshop',
    'Stores',
    'QC / Inspection',
    'Billing'
  ].freeze

  WORK_ROLES = [
    'Service Advisor',
    'Workshop Supervisor',
    'Technician',
    'Stores Clerk',
    'QC Inspector',
    'Billing Officer'
  ].freeze

  validates :work_order_number, presence: true, uniqueness: true

  before_validation :generate_work_order_number, on: :create
  before_validation :sync_vehicle_from_po_for_demo
  before_validation :embed_role_and_section_into_notes_for_demo

  # -------------------------
  # Display helpers
  # -------------------------
  def vehicle
    purchase_order&.vehicle
  end

  def po_number
    purchase_order&.po_number
  end

  # Extracts "Work Section" from notes (if present)
  def extracted_work_section
    return nil if notes.blank?
    m = notes.match(/\[Work Section:\s*(.+?)\]/)
    m ? m[1] : nil
  end

  # Extracts "Work Role" from notes (if present)
  def extracted_work_role
    return nil if notes.blank?
    m = notes.match(/\[Work Role:\s*(.+?)\]/)
    m ? m[1] : nil
  end

  private

  def generate_work_order_number
    return if work_order_number.present?

    date_part = Time.current.strftime('%Y%m%d')
    random_part = SecureRandom.hex(4).upcase
    self.work_order_number = "POS-#{date_part}-#{random_part}"
  end

  # For demo: keep vehicle_id aligned to PO's vehicle if column exists.
  # This stops "wrong values" from being selected manually.
  def sync_vehicle_from_po_for_demo
    return unless respond_to?(:vehicle_id)
    return if purchase_order_id.blank?

    self.vehicle_id = purchase_order&.vehicle_id
  end

  # For demo: store work_section/work_role inside notes so it persists.
  def embed_role_and_section_into_notes_for_demo
    # only embed if user submitted something
    return if work_section.blank? && work_role.blank?

    section = work_section.to_s.strip
    role = work_role.to_s.strip

    # remove existing embedded tags (if editing/re-saving)
    cleaned = (notes || '').gsub(/\[Work Section:.*?\]\s*/m, '').gsub(/\[Work Role:.*?\]\s*/m, '').strip

    tags = []
    tags << "[Work Section: #{section}]" if section.present?
    tags << "[Work Role: #{role}]" if role.present?

    self.notes = ([tags.join(' '), cleaned].reject(&:blank?)).join("\n").strip
  end
end
