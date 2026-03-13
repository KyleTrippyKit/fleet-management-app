# app/models/parts_request.rb
class PartsRequest < ApplicationRecord
  belongs_to :inspection
  belongs_to :inspection_job, optional: true  # Link to the specific job
  belongs_to :part, optional: true  # Make part optional for custom parts
  belongs_to :vendor_invoice, optional: true
  belongs_to :purchase_order, optional: true
  
  # Timestamp fields - these should exist in your database
  # If they don't exist, you'll need to add them via migration
  attribute :sent_to_procurement_at, :datetime
  attribute :notified_parts_coordinator_at, :datetime
  attribute :notified_billing_at, :datetime
  attribute :parts_received_at, :datetime
  
  # Association to VendorRfq through part's vendor_rfq_items
  has_many :vendor_rfq_items, through: :part
  has_many :rfqs, through: :vendor_rfq_items, source: :vendor_rfq

  validates :quantity, presence: true, numericality: { greater_than: 0 }
  
  # If it's a custom part, we need a name
  validates :custom_part_name, presence: true, if: -> { part_id.nil? }

  # Fix the enum definition - use the Rails 7+ syntax
  enum :status, {
    pending: 'pending',
    parts_coordinator_notified: 'parts_coordinator_notified',
    billing_notified: 'billing_notified',
    rfq_sent: 'rfq_sent',
    quotations_received: 'quotations_received',
    finance_review: 'finance_review',
    purchase_order_created: 'purchase_order_created',
    parts_ordered: 'parts_ordered',
    parts_received: 'parts_received',
    approved: 'approved',
    rejected: 'rejected'
  }

  scope :needing_coordinator_action, -> { where(status: [:pending, :parts_coordinator_notified]) }
  scope :needing_billing_action, -> { where(status: :billing_notified) }
  scope :needing_finance_action, -> { where(status: :finance_review) }
  scope :custom_parts, -> { where(part_id: nil) }
  scope :inventory_parts, -> { where.not(part_id: nil) }
  scope :for_job, ->(job_id) { where(inspection_job_id: job_id) }
  
  # Status helper methods
  def pending?
    status == 'pending'
  end
  
  def parts_coordinator_notified?
    status == 'parts_coordinator_notified'
  end
  
  def billing_notified?
    status == 'billing_notified'
  end
  
  def parts_ordered?
    status == 'parts_ordered'
  end
  
  def parts_received?
    status == 'parts_received'
  end

  def part_name
    part&.name || custom_part_name || "Unknown Part"
  end

  def custom?
    part_id.nil?
  end

  def inventory?
    part_id.present?
  end

  def in_stock?
    return false if custom?  # Custom parts are never in stock
    return false unless part.present?
    part.current_stock >= quantity
  end

  def notify_coordinator!
    update(status: :parts_coordinator_notified, notified_parts_coordinator_at: Time.current)
    PartsCoordinatorNotificationJob.perform_later(id) if defined?(PartsCoordinatorNotificationJob)
  end

  def notify_billing!
    update(status: :billing_notified, notified_billing_at: Time.current)
    BillingNotificationJob.perform_later(id) if defined?(BillingNotificationJob)
  end

  def create_rfq
    rfq = VendorRfq.create!(
      processing_agency_id: inspection.vehicle.agency_id,
      status: 'draft',
      notes: "Parts needed for inspection ##{inspection.id}: #{part_name}"
    )
    
    rfq.vendor_rfq_items.create!(
      part: part,
      custom_part_name: custom_part_name,
      quantity: quantity,
      description: part_name
    )
    
    rfq
  end

  def mark_parts_received!(invoice)
    update!(
      status: :parts_received,
      parts_received_at: Time.current,
      vendor_invoice: invoice
    )
    
    # Update stock only for inventory parts
    if inventory?
      part.update!(current_stock: part.current_stock + quantity)
    end
    
    inspection.check_parts_availability! if inspection.respond_to?(:check_parts_availability!)
  end
  
  # Helper method to get the most recent RFQ for this parts request
  def latest_rfq
    return nil unless part.present?
    return nil unless rfqs.any?
    
    rfqs.order(created_at: :desc).first
  rescue => e
    Rails.logger.error "Error in latest_rfq: #{e.message}"
    nil
  end
  
  # Helper method to check if there are any RFQs
  def has_rfqs?
    return false unless part.present?
    rfqs.exists?
  rescue => e
    Rails.logger.error "Error in has_rfqs?: #{e.message}"
    false
  end
  
  # Helper method to get RFQ number if available
  def rfq_number
    latest_rfq&.rfq_number
  end
  
  # Helper method to get the part number (for inventory parts)
  def part_number
    part&.part_number
  end
  
  # Helper method to get the part's current stock
  def current_stock
    return 0 if custom? || part.nil?
    part.current_stock
  end
  
  # Helper method to get the shortfall quantity
  def shortfall_quantity
    return quantity if custom? || part.nil?
    [quantity - part.current_stock, 0].max
  end
  
  # Helper method to get status display for UI
  def status_display
    case status
    when 'pending'
      'Pending Review'
    when 'parts_coordinator_notified'
      'With Coordinator'
    when 'billing_notified'
      'With Billing'
    when 'rfq_sent'
      'RFQ Sent'
    when 'quotations_received'
      'Quotes Received'
    when 'finance_review'
      'Finance Review'
    when 'purchase_order_created'
      'PO Created'
    when 'parts_ordered'
      'Ordered'
    when 'parts_received'
      'Received'
    when 'approved'
      'Approved'
    when 'rejected'
      'Rejected'
    else
      status.to_s.humanize
    end
  end
  
  # Helper method to get status badge class
  def status_badge_class
    case status
    when 'pending'
      'warning'
    when 'parts_coordinator_notified', 'billing_notified'
      'info'
    when 'rfq_sent', 'quotations_received'
      'primary'
    when 'finance_review'
      'dark'
    when 'purchase_order_created', 'parts_ordered'
      'secondary'
    when 'parts_received', 'approved'
      'success'
    when 'rejected'
      'danger'
    else
      'light'
    end
  end
end