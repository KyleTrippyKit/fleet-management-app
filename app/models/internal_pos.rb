# app/models/internal_pos.rb
class InternalPos < ApplicationRecord
  belongs_to :purchase_order, optional: true
  belongs_to :created_by, class_name: 'User'
  belongs_to :assigned_to, class_name: 'User', optional: true

  # NOTE: Vehicle is derived from purchase_order.vehicle for consistency

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

  # Virtual fields for DEMO (no migration needed)
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

  before_validation :set_work_order_number, on: :create
  before_validation :embed_role_and_section_into_notes_for_demo

  after_update :sync_with_purchase_order, if: :saved_change_to_status?
  after_create :notify_creation

  # -------------------------
  # Class Methods
  # -------------------------
  
  def self.generate_work_order_number
    date_part = Time.current.strftime('%Y%m%d')
    random_part = SecureRandom.hex(4).upcase
    "POS-#{date_part}-#{random_part}"
  end

  # -------------------------
  # Vehicle Access Methods
  # -------------------------
  def vehicle
    purchase_order&.vehicle
  end

  def vehicle_info
    vehicle || purchase_order&.vehicle
  end

  def po_number
    purchase_order&.po_number
  end

  # -------------------------
  # Display Helpers
  # -------------------------
  def extracted_work_section
    return nil if notes.blank?
    m = notes.match(/\[Work Section:\s*(.+?)\]/)
    m ? m[1] : nil
  end

  def extracted_work_role
    return nil if notes.blank?
    m = notes.match(/\[Work Role:\s*(.+?)\]/)
    m ? m[1] : nil
  end

  def short_description
    return "No description" if notes.blank?
    
    lines = notes.split("\n")
                 .reject { |line| line.start_with?('[Work Section:', '[Work Role:') }
    
    lines.first.presence || "Work order #{work_order_number}"
  end

  def qc_work_order?
    notes.to_s.include?('QC / Inspection')
  end

  def billing_work_order?
    notes.to_s.include?('Billing')
  end

  def workshop_work_order?
    notes.to_s.include?('Workshop')
  end

  def assigned_user_name
    assigned_to&.name || 'Unassigned'
  end

  private

  def set_work_order_number
    return if work_order_number.present?
    self.work_order_number = self.class.generate_work_order_number
  end

  def sync_with_purchase_order
    return unless purchase_order
    
    case status
    when 'in_progress'
      purchase_order.update!(
        vmcott_status: 'work_in_progress',
        notes: purchase_order.notes.to_s + "\n🔧 Work started on #{Time.current.strftime('%b %d')}"
      )
      Rails.logger.info "▶️ Work started on PO #{purchase_order.po_number}"
      
    when 'completed'
      if qc_work_order?
        handle_qc_completion
      elsif billing_work_order?
        handle_billing_completion
      else
        handle_work_completion
      end
      
    when 'cancelled'
      purchase_order.update!(
        notes: purchase_order.notes.to_s + "\n❌ Work cancelled: #{notes}"
      )
      Rails.logger.info "❌ Work cancelled on PO #{purchase_order.po_number}"
    end
  end

  def handle_work_completion
    return unless purchase_order
    
    purchase_order.update!(
      vmcott_status: 'internal_work_completed',
      notes: purchase_order.notes.to_s + "\n✅ Work completed on #{Time.current.strftime('%b %d')}"
    )
    
    purchase_order.notify_agency("Work completed for PO #{purchase_order.po_number}")
    
    qc_po = purchase_order.internal_pos.find_by('notes LIKE ?', '%QC / Inspection%')
    if qc_po && qc_po.status == 'pending'
      Rails.logger.info "🔍 QC inspection ready for PO #{purchase_order.po_number}"
    end
    
    Rails.logger.info "✅ Work completed on PO #{purchase_order.po_number}"
  end

  def handle_qc_completion
    return unless purchase_order
    
    purchase_order.update!(
      vmcott_status: 'ready_for_delivery',
      notes: purchase_order.notes.to_s + "\n✅ QC passed on #{Time.current.strftime('%b %d')}"
    )
    
    billing_po = purchase_order.internal_pos.find_by('notes LIKE ?', '%Billing%')
    
    unless billing_po
      purchase_order.internal_pos.create!(
        work_order_number: InternalPos.generate_work_order_number,
        created_by: created_by,
        status: 'pending',
        priority: 'normal',
        notes: "[Work Section: Billing]\n[Work Role: Billing Officer]\nPrepare final invoice for PO #{purchase_order.po_number}"
      )
      Rails.logger.info "💰 Billing work order created for PO #{purchase_order.po_number}"
    end
    
    Rails.logger.info "🚚 Vehicle ready for delivery - PO #{purchase_order.po_number}"
    purchase_order.notify_agency("Vehicle ready for pickup - PO #{purchase_order.po_number}")
  end

  def handle_billing_completion
    return unless purchase_order
    Rails.logger.info "💰 Billing completed for PO #{purchase_order.po_number}"
  end

  def notify_creation
    Rails.logger.info "📋 New work order created: #{work_order_number}"
    
    if workshop_work_order?
      Rails.logger.info "  → Assigned to Workshop (Priority: #{priority})"
    elsif qc_work_order?
      Rails.logger.info "  → Assigned to QC Inspection"
    elsif billing_work_order?
      Rails.logger.info "  → Assigned to Billing"
    end
  end

  def embed_role_and_section_into_notes_for_demo
    return if work_section.blank? && work_role.blank?

    section = work_section.to_s.strip
    role = work_role.to_s.strip

    cleaned = (notes || '').gsub(/\[Work Section:.*?\]\s*/m, '').gsub(/\[Work Role:.*?\]\s*/m, '').strip

    tags = []
    tags << "[Work Section: #{section}]" if section.present?
    tags << "[Work Role: #{role}]" if role.present?

    self.notes = ([tags.join(' '), cleaned].reject(&:blank?)).join("\n").strip
  end
end