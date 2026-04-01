# app/models/parts_request.rb
class PartsRequest < ApplicationRecord
  belongs_to :inspection
  belongs_to :inspection_job, optional: true
  belongs_to :part, optional: true
  belongs_to :requested_by, class_name: 'User', optional: true
  belongs_to :approved_by, class_name: 'User', optional: true
  belongs_to :rejected_by, class_name: 'User', optional: true
  belongs_to :issued_by, class_name: 'User', optional: true
  belongs_to :purchase_order, optional: true
  belongs_to :vendor_invoice, optional: true

  # Simplified status enum
  enum :status, {
    requested: 'requested',
    approved: 'approved',
    rejected: 'rejected',
    needs_order: 'needs_order',
    ordered: 'ordered',
    received: 'received',
    issued: 'issued'
  }, default: :requested

  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :custom_part_name, presence: true, if: -> { part_id.nil? }

  # Scopes
  scope :pending_approval, -> { where(status: :requested) }
  scope :approved_requests, -> { where(status: :approved) }
  scope :rejected_requests, -> { where(status: :rejected) }
  scope :needing_order, -> { where(status: :needs_order) }
  scope :ordered_requests, -> { where(status: :ordered) }
  scope :received_requests, -> { where(status: :received) }
  scope :issued_requests, -> { where(status: :issued) }
  scope :custom_parts, -> { where(part_id: nil) }
  scope :inventory_parts, -> { where.not(part_id: nil) }

  # =====================================================
  # HELPER METHODS
  # =====================================================

  def available?
    return false if custom?
    return false unless part.present?
    part.current_stock >= quantity
  end

  def custom?
    part_id.nil?
  end

  def inventory?
    part_id.present?
  end

  def in_stock?
    return false if custom?
    return false unless part.present?
    part.current_stock >= quantity
  end

  def part_name
    part&.name || custom_part_name || "Unknown Part"
  end

  def shortfall_quantity
    return quantity if custom? || part.nil?
    [quantity - part.current_stock, 0].max
  end

  # =====================================================
  # APPROVAL METHODS
  # =====================================================

  def approve!(user)
    update!(
      status: :approved,
      approved_by: user,
      approved_at: Time.current
    )
    
    # Notify mechanic who requested the part
    if inspection_job&.assigned_mechanic
      begin
        Notification.create!(
          user: inspection_job.assigned_mechanic,
          title: "Parts Request Approved",
          message: "Your request for #{quantity}x #{part_name} has been approved by #{user.name}.",
          link: "/vmcott/mechanic/jobs/#{inspection_job_id}",
          notification_type: 'success',
          notifiable: self
        )
      rescue => e
        Rails.logger.error "Failed to notify mechanic: #{e.message}"
      end
    end
    
    # Notify the requester if different from assigned mechanic
    if requested_by.present? && requested_by != inspection_job&.assigned_mechanic
      begin
        Notification.create!(
          user: requested_by,
          title: "Parts Request Approved",
          message: "Your parts request for #{quantity}x #{part_name} has been approved by #{user.name}.",
          link: "/vmcott/mechanic/dashboard",
          notification_type: 'success',
          notifiable: self
        )
      rescue => e
        Rails.logger.error "Failed to notify requester: #{e.message}"
      end
    end
    
    # Check inventory - if in stock, notify inventory manager to issue
    if in_stock?
      notify_inventory_manager
    else
      # Update status to needs_order and notify inventory manager to handle procurement
      update!(status: :needs_order)
      notify_inventory_manager_for_procurement
    end
  end

  def reject!(user, reason)
    update!(
      status: :rejected,
      rejected_by: user,
      rejected_at: Time.current,
      rejection_reason: reason
    )
    
    # Notify mechanic who requested the part
    if inspection_job&.assigned_mechanic
      begin
        Notification.create!(
          user: inspection_job.assigned_mechanic,
          title: "Parts Request Rejected",
          message: "Your request for #{quantity}x #{part_name} was rejected by #{user.name}. Reason: #{reason}",
          link: "/vmcott/mechanic/jobs/#{inspection_job_id}",
          notification_type: 'danger',
          notifiable: self
        )
      rescue => e
        Rails.logger.error "Failed to notify mechanic: #{e.message}"
      end
    end
    
    # Notify the requester if different from assigned mechanic
    if requested_by.present? && requested_by != inspection_job&.assigned_mechanic
      begin
        Notification.create!(
          user: requested_by,
          title: "Parts Request Rejected",
          message: "Your parts request for #{quantity}x #{part_name} was rejected. Reason: #{reason}",
          link: "/vmcott/mechanic/dashboard",
          notification_type: 'danger',
          notifiable: self
        )
      rescue => e
        Rails.logger.error "Failed to notify requester: #{e.message}"
      end
    end
  end

  def issue!(user)
    update!(
      status: :issued,
      issued_by: user,
      issued_at: Time.current
    )
    
    # Update part stock
    if inventory? && part.present?
      part.update!(current_stock: part.current_stock - quantity)
    end
    
    # Notify mechanic
    if inspection_job&.assigned_mechanic
      begin
        Notification.create!(
          user: inspection_job.assigned_mechanic,
          title: "Parts Issued",
          message: "#{quantity}x #{part_name} has been issued for job ##{inspection_job_id} by #{user.name}.",
          link: "/vmcott/mechanic/jobs/#{inspection_job_id}",
          notification_type: 'info',
          notifiable: self
        )
      rescue => e
        Rails.logger.error "Failed to notify mechanic: #{e.message}"
      end
    end
  end

  def mark_ordered!(user, po_id = nil)
    update!(
      status: :ordered,
      purchase_order_id: po_id,
      ordered_at: Time.current
    )
    
    # Notify procurement that order was placed
    procurement_users = User.where(role: 'procurement')
    if procurement_users.any?
      begin
        notification_data = {
          user_id: procurement_users.pluck(:id),
          title: "Parts Ordered",
          message: "#{quantity}x #{part_name} has been ordered via PO ##{po_id}.",
          notification_type: 'info',
          notifiable: self
        }
        notification_data[:link] = "/vmcott/procurement/purchase_orders/#{po_id}" if po_id
        Notification.create!(notification_data)
      rescue => e
        Rails.logger.error "Failed to notify procurement: #{e.message}"
      end
    end
    
    # Notify inventory manager
    notify_inventory_manager_order_placed(po_id)
  end

  def mark_received!(user, invoice = nil)
    update!(
      status: :received,
      parts_received_at: Time.current,
      vendor_invoice: invoice
    )
    
    # Update stock for inventory parts
    if inventory? && part.present?
      part.update!(current_stock: part.current_stock + quantity)
    end
    
    # Notify mechanic
    if inspection_job&.assigned_mechanic
      begin
        Notification.create!(
          user: inspection_job.assigned_mechanic,
          title: "Parts Received",
          message: "#{quantity}x #{part_name} has been received and is ready for use.",
          link: "/vmcott/mechanic/jobs/#{inspection_job_id}",
          notification_type: 'success',
          notifiable: self
        )
      rescue => e
        Rails.logger.error "Failed to notify mechanic: #{e.message}"
      end
    end
    
    # Notify inventory manager that parts are now in stock
    notify_inventory_manager_parts_received
    
    # Check if all parts are now available
    inspection.check_parts_availability! if inspection.respond_to?(:check_parts_availability!)
  end

  # =====================================================
  # NOTIFICATION METHODS
  # =====================================================

  def notify_inventory_manager
    inventory_manager_ids = User.where(role: 'inventory_manager').pluck(:id)
    
    if inventory_manager_ids.any?
      begin
        Notification.create!(
          user_id: inventory_manager_ids,
          title: "Parts Ready to Issue",
          message: "Part #{part_name} x#{quantity} is in stock and ready for issue to job ##{inspection_job_id}.",
          link: "/vmcott/inventory_manager/parts_requests/#{id}",
          notification_type: 'info',
          notifiable: self
        )
      rescue => e
        Rails.logger.error "Failed to notify inventory managers: #{e.message}"
      end
    else
      Rails.logger.warn "No inventory managers found. Cannot send notification for parts request ##{id}"
    end
  end

  def notify_inventory_manager_for_procurement
    inventory_manager_ids = User.where(role: 'inventory_manager').pluck(:id)
    
    if inventory_manager_ids.any?
      begin
        Notification.create!(
          user_id: inventory_manager_ids,
          title: "Parts Need Ordering",
          message: "Part #{part_name} x#{quantity} is not in stock. Please create a purchase order to procure these parts.",
          link: "/vmcott/inventory_manager/parts_requests/#{id}",
          notification_type: 'warning',
          notifiable: self
        )
      rescue => e
        Rails.logger.error "Failed to notify inventory managers for procurement: #{e.message}"
      end
    else
      Rails.logger.warn "No inventory managers found. Cannot send procurement notification for parts request ##{id}"
    end
  end

  def notify_inventory_manager_order_placed(po_id)
    inventory_manager_ids = User.where(role: 'inventory_manager').pluck(:id)
    
    if inventory_manager_ids.any?
      begin
        Notification.create!(
          user_id: inventory_manager_ids,
          title: "Parts Order Placed",
          message: "PO ##{po_id} has been created for #{quantity}x #{part_name}. Awaiting receipt.",
          link: "/vmcott/inventory_manager/purchase_orders/#{po_id}",
          notification_type: 'info',
          notifiable: self
        )
      rescue => e
        Rails.logger.error "Failed to notify inventory managers: #{e.message}"
      end
    end
  end

  def notify_inventory_manager_parts_received
    inventory_manager_ids = User.where(role: 'inventory_manager').pluck(:id)
    
    if inventory_manager_ids.any?
      begin
        Notification.create!(
          user_id: inventory_manager_ids,
          title: "Parts Received",
          message: "#{quantity}x #{part_name} has been received and added to inventory. Ready for issue.",
          link: "/vmcott/inventory_manager/parts_requests/#{id}",
          notification_type: 'success',
          notifiable: self
        )
      rescue => e
        Rails.logger.error "Failed to notify inventory managers: #{e.message}"
      end
    end
  end

  # =====================================================
  # STATUS HELPERS
  # =====================================================

  def requested?
    status == 'requested'
  end

  def approved?
    status == 'approved'
  end

  def rejected?
    status == 'rejected'
  end

  def needs_order?
    status == 'needs_order'
  end

  def ordered?
    status == 'ordered'
  end

  def received?
    status == 'received'
  end

  def issued?
    status == 'issued'
  end

  def status_display
    case status
    when 'requested' then 'Pending Approval'
    when 'approved' then 'Approved'
    when 'rejected' then 'Rejected'
    when 'needs_order' then 'Needs Order - Awaiting PO Creation'
    when 'ordered' then 'Ordered - Awaiting Delivery'
    when 'received' then 'Received - Ready for Issue'
    when 'issued' then 'Issued to Mechanic'
    else status.to_s.humanize
    end
  end

  def status_badge_class
    case status
    when 'requested' then 'warning'
    when 'approved' then 'success'
    when 'rejected' then 'danger'
    when 'needs_order' then 'danger'
    when 'ordered' then 'primary'
    when 'received' then 'success'
    when 'issued' then 'info'
    else 'secondary'
    end
  end
end