# app/controllers/vmcott/inventory_manager/dashboard_controller.rb
class Vmcott::InventoryManager::DashboardController < ApplicationController
  # Skip the dashboard caching for this controller
  skip_around_action :cache_dashboard_data, if: :dashboard_controller?
  
  layout 'application'
  before_action :authenticate_user!
  before_action :require_inventory_manager
  
  # Disable all caching for this controller
  before_action :disable_caching

  def index
    # Stats for KPI cards - Updated to match workshop PartsRequest statuses
    @stats = {
      # Workshop uses 'requested' and 'approved' for pending review
      pending_parts: PartsRequest.where(status: ['requested', 'approved']).count,
      # Workshop uses 'needs_order' for procurement stage
      pending_procurement: PartsRequest.where(status: 'needs_order').count,
      pending_finance: PartsRequest.where(status: 'finance_review').count,
      # Workshop uses 'ordered' for ordered status
      ordered_count: PartsRequest.where(status: 'ordered').count,
      # Workshop uses 'received' for received status
      parts_received: PartsRequest.where(status: 'received').count,
      low_stock_count: Part.where('current_stock <= reorder_point').count,
      in_stock_count: Part.where('current_stock > reorder_point').count,
      out_of_stock_count: Part.where('current_stock <= 0').count,
      approved_po_count: PurchaseOrder.where(status: 'approved').count,
      ordered_po_count: PurchaseOrder.where(status: 'ordered').count,
      ready_for_workshop_count: Inspection.where(status: 'ready_for_workshop').count,
      total_parts: Part.count,
      monthly_ordered: PartsRequest.where('created_at > ?', 30.days.ago).count,
      total_po_value: PurchaseOrder.where(status: 'ordered').sum(:amount),
      avg_delivery_days: calculate_avg_delivery_days
    }

    # 🔥 FIXED: Pending parts - needs review (workshop uses 'requested' and 'approved')
    @pending_parts = PartsRequest
      .includes(inspection: :vehicle, part: [], inspection_job: [])
      .where(status: ['requested', 'approved'])
      .order(created_at: :desc)
      .limit(20)

    # 🔥 FIXED: With Procurement - needs ordering (workshop uses 'needs_order')
    @pending_procurement = PartsRequest
      .includes(inspection: :vehicle, part: [])
      .where(status: 'needs_order')
      .order(updated_at: :desc)
      .limit(20)

    # Finance Review (if your workflow uses this)
    @pending_finance = PartsRequest
      .includes(inspection: :vehicle)
      .where(status: 'finance_review')
      .order(updated_at: :desc)
      .limit(20)

    # 🔥 FIXED: Ordered - Awaiting delivery (workshop uses 'ordered')
    @ordered_requests = PartsRequest
      .includes(:purchase_order, :part, inspection: :vehicle)
      .where(status: 'ordered')
      .order(updated_at: :desc)
      .limit(20)
    
    # 🔥 FIXED: Received - Ready for workshop (workshop uses 'received')
    @parts_received = PartsRequest
      .includes(inspection: :vehicle, part: [])
      .where(status: 'received')
      .order(updated_at: :desc)
      .limit(20)
    
    # Ready for workshop - Complete inspections
    @ready_for_workshop = Inspection
      .where(status: 'ready_for_workshop')
      .includes(:vehicle)
      .order(updated_at: :desc)
      .limit(20)

    # Low stock alerts
    @low_stock_parts = Part
      .where('current_stock <= reorder_point')
      .order(current_stock: :asc)
      .limit(20)

    # Approved POs
    @approved_pos = PurchaseOrder
      .includes(:purchase_order_items)
      .where(status: 'approved')
      .order(approved_at: :desc)
      .limit(10)

    # Ordered POs
    @ordered_pos = PurchaseOrder
      .includes(:purchase_order_items)
      .where(status: 'ordered')
      .order(ordered_at: :desc)
      .limit(10)
    
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    render 'vmcott/inventory_manager/dashboard/index'
  end

  # Approve and allocate in-stock part to job
  def mark_in_stock
    parts_request = PartsRequest.find(params[:id])
    
    ActiveRecord::Base.transaction do
      # Update part request to 'issued' status (part given to mechanic)
      parts_request.update!(
        status: 'issued',
        in_stock: true,
        issued_at: Time.current,
        issued_by_id: current_user.id
      )
      
      # Deduct from inventory
      if parts_request.part && parts_request.part.current_stock >= parts_request.quantity
        parts_request.part.update!(
          current_stock: parts_request.part.current_stock - parts_request.quantity
        )
        
        # Create inventory transaction record
        InventoryTransaction.create!(
          inventory_item: parts_request.part,
          quantity: -parts_request.quantity,
          transaction_type: 'consumption',
          reference: parts_request,
          notes: "Issued for job ##{parts_request.inspection_job_id} - #{parts_request.inspection_job&.description}",
          user_id: current_user.id
        )
        
        # 🔥 Notify mechanic that part is available
        if parts_request.inspection_job&.assigned_mechanic
          Notification.create!(
            user: parts_request.inspection_job.assigned_mechanic,
            title: "🔧 Part Ready for Pickup",
            message: "#{parts_request.quantity}x #{parts_request.part&.name || parts_request.custom_part_name} has been issued for your job. Ready at parts counter.",
            link: vmcott_mechanic_job_path(parts_request.inspection_job),
            notification_type: 'success',
            notifiable: parts_request
          )
        end
      end
    end
    
    flash[:notice] = "✓ Part approved and issued to job ##{parts_request.inspection_job_id}"
    redirect_to vmcott_inventory_manager_dashboard_path
    
  rescue => e
    Rails.logger.error "Error in mark_in_stock: #{e.message}"
    flash[:alert] = "Failed to approve part: #{e.message}"
    redirect_to vmcott_inventory_manager_dashboard_path
  end

  # Send out-of-stock part to procurement for ordering
  def send_to_procurement
    parts_request = PartsRequest.find(params[:id])
    
    # Update part request to 'needs_order' status
    update_params = {
      status: 'needs_order'
    }
    
    # Add timestamp fields if they exist
    if parts_request.respond_to?(:sent_to_procurement_at)
      update_params[:sent_to_procurement_at] = Time.current
    end
    
    if parts_request.respond_to?(:notified_parts_coordinator_at)
      update_params[:notified_parts_coordinator_at] = Time.current
    end
    
    parts_request.update(update_params)
    
    flash[:notice] = "📦 Part sent to procurement team for ordering"
    redirect_to vmcott_inventory_manager_dashboard_path
    
  rescue => e
    Rails.logger.error "Error in send_to_procurement: #{e.message}"
    flash[:alert] = "Failed to send to procurement: #{e.message}"
    redirect_to vmcott_inventory_manager_dashboard_path
  end

  # Pass completed job to workshop when all parts are ready
  def pass_to_workshop
    inspection = Inspection.find(params[:id])
    
    # Update inspection status
    inspection.update(status: 'parts_ready')
    
    # 🔥 ONLY notify workshop supervisor - NOT mechanics yet
    if inspection.supervisor.present?
      Notification.create!(
        user_id: inspection.supervisor.id,
        title: "📋 Parts Ready - Create Quotation",
        message: "All parts for #{inspection.vehicle.license_plate} have been received. Please create a quotation for customer approval.",
        link: vmcott_workshop_supervisor_quotation_creation_path(inspection),
        notification_type: 'info',
        notifiable: inspection
      )
    end
    
    flash[:success] = "✓ Parts marked as ready. Workshop supervisor will create quotation."
    redirect_to vmcott_inventory_manager_dashboard_path
  end

  # Mark purchase order as ordered
  def mark_po_ordered
    purchase_order = PurchaseOrder.find(params[:id])
    
    ActiveRecord::Base.transaction do
      purchase_order.update(status: 'ordered', ordered_at: Time.current)
      
      # Update associated parts requests to 'ordered' status
      purchase_order.parts_requests.each do |pr|
        pr.update!(
          status: 'ordered',
          ordered_at: Time.current,
          purchase_order_id: purchase_order.id
        )
        
        # 🔥 Notify requester that parts are ordered
        if pr.requested_by.present?
          Notification.create!(
            user: pr.requested_by,
            title: "📦 Parts Ordered",
            message: "#{pr.quantity}x #{pr.part&.name || pr.custom_part_name} has been ordered. PO ##{purchase_order.po_number}",
            link: vmcott_mechanic_dashboard_path,
            notification_type: 'info',
            notifiable: pr
          )
        end
      end
    end
    
    redirect_to vmcott_inventory_manager_dashboard_path, notice: "✓ PO marked as ordered"
    
  rescue => e
    Rails.logger.error "Error in mark_po_ordered: #{e.message}"
    flash[:alert] = "Failed to mark PO as ordered: #{e.message}"
    redirect_to vmcott_inventory_manager_dashboard_path
  end

  # 🔥 UPDATED: Mark purchase order as received and update inventory with notifications
  def mark_po_received
    purchase_order = PurchaseOrder.find(params[:id])
    
    ActiveRecord::Base.transaction do
      purchase_order.update(status: 'received', received_at: Time.current)
      
      received_count = 0
      supervisor_notified = false
      mechanic_notified = false
      
      purchase_order.parts_requests.each do |pr|
        # Update parts request to 'received' status
        pr.update!(
          status: 'received',
          parts_received_at: Time.current
        )
        received_count += 1
        
        # Update inventory stock levels
        if pr.part
          old_stock = pr.part.current_stock
          new_stock = old_stock + pr.quantity
          
          pr.part.update!(current_stock: new_stock)
          
          # Create inventory transaction record
          InventoryTransaction.create!(
            inventory_item: pr.part,
            quantity: pr.quantity,
            transaction_type: 'receipt',
            reference: purchase_order,
            notes: "Received via PO ##{purchase_order.po_number}",
            user_id: current_user.id
          )
          
          Rails.logger.info "📦 Stock updated for #{pr.part.name}: #{old_stock} → #{new_stock}"
        end
        
        # 🔥 NOTIFY WORKSHOP SUPERVISOR that parts are received
        if pr.inspection && pr.inspection.supervisor.present?
          supervisor_notified = true
          Notification.create!(
            user: pr.inspection.supervisor,
            title: "📦 Parts Received - Ready for Quotation",
            message: "#{pr.quantity}x #{pr.part&.name || pr.custom_part_name} has been received for #{pr.inspection.vehicle&.license_plate}. Ready to create quotation.",
            link: vmcott_workshop_supervisor_quotation_creation_path(pr.inspection),
            notification_type: 'success',
            notifiable: pr
          )
          Rails.logger.info "Notified supervisor #{pr.inspection.supervisor.name} about parts receipt"
        end
        
        # 🔥 Notify requester (mechanic) that parts are received
        if pr.requested_by.present?
          mechanic_notified = true
          Notification.create!(
            user: pr.requested_by,
            title: "📦 Parts Received",
            message: "#{pr.quantity}x #{pr.part&.name || pr.custom_part_name} has been received and is ready for pickup.",
            link: vmcott_mechanic_dashboard_path,
            notification_type: 'success',
            notifiable: pr
          )
        end
        
        # Check if all parts for this inspection are now available
        inspection = pr.inspection
        if inspection && inspection.all_parts_available?
          inspection.update!(
            status: 'ready_for_workshop',
            parts_ready_at: Time.current
          )
          notify_mechanics_workshop_ready(inspection)
        end
      end
      
      # 🔥 NEW: Notify inventory manager that parts are now in stock
      if received_count > 0
        Notification.create!(
          user: current_user,
          title: "📦 Inventory Updated",
          message: "#{received_count} part(s) received and added to inventory. Current stock levels updated.",
          link: vmcott_inventory_manager_dashboard_path,
          notification_type: 'success',
          notifiable: purchase_order
        )
      end
      
      notice = "✓ PO marked as received. #{received_count} parts updated in inventory."
      notice += " Supervisor notified." if supervisor_notified
      notice += " Mechanic notified." if mechanic_notified
      
      redirect_to vmcott_inventory_manager_dashboard_path, notice: notice
    end
    
  rescue => e
    Rails.logger.error "Error in mark_po_received: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    flash[:alert] = "Failed to mark PO as received: #{e.message}"
    redirect_to vmcott_inventory_manager_dashboard_path
  end

  # Receive parts from an order (alternative endpoint)
  def receive_parts
    purchase_order = PurchaseOrder.find(params[:purchase_order_id])
    parts_request = PartsRequest.find(params[:parts_request_id])
    
    ActiveRecord::Base.transaction do
      purchase_order.update(status: 'received', received_at: Time.current) if purchase_order.status != 'received'
      
      parts_request.update!(
        status: 'received',
        parts_received_at: Time.current
      )
      
      # Update inventory
      if parts_request.part
        old_stock = parts_request.part.current_stock
        new_stock = old_stock + parts_request.quantity
        
        parts_request.part.update!(current_stock: new_stock)
        
        InventoryTransaction.create!(
          inventory_item: parts_request.part,
          quantity: parts_request.quantity,
          transaction_type: 'receipt',
          reference: purchase_order,
          notes: "Received via PO ##{purchase_order.po_number}",
          user_id: current_user.id
        )
        
        Rails.logger.info "📦 Stock updated for #{parts_request.part.name}: #{old_stock} → #{new_stock}"
      end
      
      # 🔥 Notify supervisor about this specific part
      if parts_request.inspection && parts_request.inspection.supervisor.present?
        Notification.create!(
          user: parts_request.inspection.supervisor,
          title: "📦 Part Received - #{parts_request.part&.name || parts_request.custom_part_name}",
          message: "#{parts_request.quantity}x #{parts_request.part&.name || parts_request.custom_part_name} has been received for #{parts_request.inspection.vehicle&.license_plate}.",
          link: vmcott_workshop_supervisor_quotation_creation_path(parts_request.inspection),
          notification_type: 'info',
          notifiable: parts_request
        )
      end
      
      # 🔥 Notify requester
      if parts_request.requested_by.present?
        Notification.create!(
          user: parts_request.requested_by,
          title: "📦 Part Received",
          message: "#{parts_request.quantity}x #{parts_request.part&.name || parts_request.custom_part_name} has been received.",
          link: vmcott_mechanic_dashboard_path,
          notification_type: 'success',
          notifiable: parts_request
        )
      end
      
      # 🔥 Notify inventory manager
      Notification.create!(
        user: current_user,
        title: "📦 Part Received - Inventory Updated",
        message: "#{parts_request.quantity}x #{parts_request.part&.name || parts_request.custom_part_name} added to inventory.",
        link: vmcott_inventory_manager_dashboard_path,
        notification_type: 'success',
        notifiable: purchase_order
      )
      
      # Check if inspection is now ready
      inspection = parts_request.inspection
      if inspection && inspection.all_parts_available?
        inspection.update!(
          status: 'ready_for_workshop',
          parts_ready_at: Time.current
        )
        notify_mechanics_workshop_ready(inspection)
        flash[:notice] = "✓ Parts received. All parts ready! Job passed to workshop. Supervisor notified."
      else
        flash[:notice] = "✓ Parts marked as received. Supervisor notified. Inventory updated."
      end
    end
    
    redirect_to vmcott_inventory_manager_dashboard_path
    
  rescue => e
    Rails.logger.error "Error in receive_parts: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    flash[:alert] = "Failed to receive parts: #{e.message}"
    redirect_to vmcott_inventory_manager_dashboard_path
  end

  # RFQ Management
  def create_rfq
    parts_request = PartsRequest.find(params[:parts_request_id])
    
    part = parts_request.part
    unit_of_measure = part&.unit_of_measure || 'each'
    rfq_number = generate_rfq_number
    
    vendor_rfq = VendorRfq.new(
      rfq_number: rfq_number,
      processing_agency_id: current_user.agency_id,
      status: 'draft',
      notes: "Created from parts request ##{parts_request.id} for #{part&.name || parts_request.custom_part_name}"
    )
    
    vendor_rfq.vendor_rfq_items.build(
      part_id: parts_request.part_id,
      quantity: parts_request.quantity,
      custom_part_name: parts_request.custom_part_name,
      description: part&.name,
      unit_of_measure: unit_of_measure
    )
    
    if vendor_rfq.save
      parts_request.update!(
        status: 'needs_order',
        sent_to_procurement_at: Time.current
      )
      
      redirect_to vmcott_vendor_rfqs_path, notice: "RFQ ##{rfq_number} created successfully."
    else
      redirect_to vmcott_inventory_manager_dashboard_path, 
                  alert: "Failed to create RFQ: #{vendor_rfq.errors.full_messages.join(', ')}"
    end
  rescue => e
    Rails.logger.error "Error in create_rfq: #{e.message}"
    redirect_to vmcott_inventory_manager_dashboard_path, alert: "Failed to create RFQ: #{e.message}"
  end

  def send_rfq
    rfq = VendorRfq.find(params[:id])
    rfq.update(status: 'sent', sent_date: Time.current)
    redirect_to vmcott_inventory_manager_dashboard_path, notice: "RFQ sent to suppliers"
  rescue => e
    Rails.logger.error "Error in send_rfq: #{e.message}"
    redirect_to vmcott_inventory_manager_dashboard_path, alert: "Failed to send RFQ: #{e.message}"
  end

  def compare_quotations
    @rfq = VendorRfq.find(params[:id])
    @quotations = @rfq.vendor_quotations.includes(:supplier)
    
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    render 'vmcott/inventory_manager/dashboard/compare_quotations'
  end

  def accept_quotation
    quotation = VendorQuotation.find(params[:id])
    quotation.update(status: 'accepted')
    
    if quotation.vendor_rfq
      quotation.vendor_rfq.update(status: 'quotation_accepted')
    end
    
    redirect_to vmcott_inventory_manager_dashboard_path, notice: "Quotation accepted. Finance team will process."
  rescue => e
    Rails.logger.error "Error in accept_quotation: #{e.message}"
    redirect_to vmcott_inventory_manager_dashboard_path, alert: "Failed to accept quotation: #{e.message}"
  end

  # Get low stock parts for reordering
  def low_stock
    @low_stock_parts = Part.where('current_stock <= reorder_point')
                           .includes(:supplier)
                           .order(current_stock: :asc)
                           .page(params[:page])
                           .per(50)
    
    respond_to do |format|
      format.html { render 'vmcott/inventory_manager/low_stock' }
      format.csv do
        send_data generate_low_stock_csv(@low_stock_parts), 
                  filename: "low_stock_parts_#{Date.current}.csv"
      end
    end
  end

  # Generate reorder suggestions
  def reorder_suggestions
    @parts = []
    
    Part.where('current_stock <= reorder_point * 1.5').each do |part|
      days_of_supply = calculate_days_of_supply(part)
      avg_monthly_consumption = calculate_avg_monthly_consumption(part)
      suggested_qty = [part.reorder_point - part.current_stock, part.minimum_stock].max
      
      @parts << {
        part: part,
        days_of_supply: days_of_supply,
        avg_monthly_consumption: avg_monthly_consumption,
        suggested_quantity: suggested_qty,
        supplier: part.supplier
      }
    end
    
    render 'vmcott/inventory_manager/reorder_suggestions'
  end

  private

  def require_inventory_manager
    unless current_user.inventory_manager? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Inventory Manager access only."
    end
  end
  
  def disable_caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end
  
  def generate_rfq_number
    prefix = "RFQ-#{Time.current.strftime('%Y%m%d')}"
    today_rfqs = VendorRfq.where("rfq_number LIKE ?", "#{prefix}-%")
    
    if today_rfqs.any?
      last_number = today_rfqs.order(:rfq_number).last.rfq_number.split('-').last.to_i
      next_number = last_number + 1
    else
      next_number = 1
    end
    
    "#{prefix}-#{next_number.to_s.rjust(4, '0')}"
  end
  
  def calculate_avg_delivery_days
    completed_orders = PurchaseOrder.where.not(ordered_at: nil).where.not(received_at: nil)
    if completed_orders.any?
      total_days = completed_orders.sum { |po| (po.received_at.to_date - po.ordered_at.to_date).to_i }
      (total_days / completed_orders.count).round(1)
    else
      7.0
    end
  end
  
  def calculate_days_of_supply(part)
    recent_usage = part.parts_requests.where('created_at > ?', 30.days.ago).sum(:quantity)
    return nil if recent_usage == 0
    
    daily_usage = recent_usage.to_f / 30
    (part.current_stock / daily_usage).round(1)
  end
  
  def calculate_avg_monthly_consumption(part)
    usage = part.parts_requests.where('created_at > ?', 90.days.ago).sum(:quantity)
    (usage / 3).round
  end
  
  def generate_low_stock_csv(parts)
    CSV.generate(headers: true) do |csv|
      csv << ['Part Name', 'Part Number', 'Category', 'Current Stock', 'Minimum Stock', 'Reorder Point', 'Supplier', 'Status']
      parts.each do |part|
        csv << [
          part.name,
          part.part_number,
          part.category,
          part.current_stock,
          part.minimum_stock,
          part.reorder_point,
          part.supplier&.name,
          part.current_stock <= part.minimum_stock ? 'Critical' : 'Low'
        ]
      end
    end
  end
  
  def notify_mechanics_workshop_ready(inspection)
    mechanic_ids = User.where(role: 'mechanic').pluck(:id)
    
    if mechanic_ids.any?
      mechanic_ids.each do |mechanic_id|
        Notification.create!(
          user_id: mechanic_id,
          title: "🚗 Vehicle Ready for Repair",
          message: "All parts for #{inspection.vehicle.license_plate} (#{inspection.vehicle.make} #{inspection.vehicle.model}) are available. Ready for workshop.",
          link: vmcott_mechanic_dashboard_path,
          notifiable_type: 'Inspection',
          notifiable_id: inspection.id,
          notification_type: 'success'
        )
      end
    end
    
    # Create vehicle status record
    VehicleStatus.create!(
      vehicle: inspection.vehicle,
      created_by: current_user,
      status: 'ready_for_workshop',
      current: true,
      notes: "All parts available. Ready for mechanic."
    )
  rescue => e
    Rails.logger.error "Failed to notify mechanics: #{e.message}"
  end
end