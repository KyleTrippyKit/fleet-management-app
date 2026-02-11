# frozen_string_literal: true

class VendorQuotation < ApplicationRecord
  STATUSES = %w[draft received accepted rejected].freeze

  belongs_to :vendor_rfq
  belongs_to :supplier
  belongs_to :purchase_order, optional: true  # ✅ NEW LINK

  has_many :vendor_quotation_lines, dependent: :destroy
  accepts_nested_attributes_for :vendor_quotation_lines, allow_destroy: true

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :supplier_id, presence: true

  # ✅ Keep these useful scopes
  scope :accepted, -> { where(status: "accepted") }
  scope :rejected, -> { where(status: "rejected") }
  scope :received, -> { where(status: "received") }
  scope :draft,    -> { where(status: "draft") }

  # ✅ Keep these helpful status check methods
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
end