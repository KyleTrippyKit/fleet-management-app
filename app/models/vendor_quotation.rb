# app/models/vendor_quotation.rb
# frozen_string_literal: true

class VendorQuotation < ApplicationRecord
  # Add Active Storage attachment
  has_one_attached :attachment

  STATUSES = %w[draft received accepted rejected].freeze

  belongs_to :vendor_rfq
  belongs_to :supplier
  belongs_to :purchase_order, optional: true

  has_many :vendor_quotation_lines, dependent: :destroy
  accepts_nested_attributes_for :vendor_quotation_lines, allow_destroy: true

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :supplier_id, presence: true

  # Set default status for new records
  after_initialize :set_default_status, if: :new_record?

  # Scopes
  scope :accepted, -> { where(status: "accepted") }
  scope :rejected, -> { where(status: "rejected") }
  scope :received, -> { where(status: "received") }
  scope :draft,    -> { where(status: "draft") }

  # Status check methods
  def accepted?
    status == "accepted"
  end

  def rejected?
    status == "rejected"
  end

  def received?
    status == "received"
  end

  def draft?
    status == "draft"
  end

  # Total of all lines
  def total_amount
    vendor_quotation_lines.sum("COALESCE(total_price, 0)")
  end

  # Get supplier name safely
  def supplier_name
    supplier&.name || "Unknown Supplier"
  end

  # Helper method to check if attachment exists
  def has_attachment?
    attachment.attached?
  end

  private

  def set_default_status
    self.status ||= 'draft'
  end
end