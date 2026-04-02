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
    # Stats for KPI cards
    @stats = {
      pending_parts: PartsRequest.where(status: 'pending').count,
      pending_procurement: PartsRequest.where(status: 'parts_coordinator_notified').count,
      pending_finance: PartsRequest.where(status: 'finance_review').count,
      ordered_count: PartsRequest.where(status: 'parts_ordered').count,
      parts_received: PartsRequest.where(status: 'parts_received').count,
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

    # Pending parts - needs review
    @pending_parts = PartsRequest.includes(inspection: :vehicle, part: [])
                                  .where(status: 'pending')
                                  .order(created_at: :desc)
                                  .limit(20)

    # With Procurement - RFQ sent
    @pending_procurement = PartsRequest.includes(inspection: :vehicle)
                                        .where(status: 'parts_coordinator_notified')
                                        .order(updated_at: :desc)
                                        .limit(20)

    # Finance Review
    @pending_finance = PartsRequest.includes(inspection: :vehicle)
                                    .where(status: 'finance_review')
                                    .order(updated_at: :desc)
                                    .limit(20)

    # Ordered - Awaiting delivery
    @ordered_requests = PartsRequest.includes(:purchase_order)
                                     .where(status: 'parts_ordered')
                                     .order(updated_at: :desc)
                                     .limit(20)
    
    # Received - Ready for workshop
    @parts_received = PartsRequest.includes(inspection: :vehicle)
                                   .where(status: 'parts_received')
                                   .order(updated_at: :desc)
                                   .limit(20)
    
    # Ready for workshop - Complete inspections
    @ready_for_workshop = Inspection.where(status: 'ready_for_workshop')
                                    .includes(:vehicle)
                                    .order(updated_at: :desc)
                                    .limit(20)

    # Low stock alerts
    @low_stock_parts = Part.where('current_stock <= reorder_point')
                           .order(current_stock: :asc)
                           .limit(20)

    # Approved POs
    @approved_pos = PurchaseOrder.includes(:purchase_order_items)
                                  .where(status: 'approved')
                                  .order(approved_at: :desc)
                                  .limit(10)

    # Ordered POs
    @ordered_pos = PurchaseOrder.includes(:purchase_order_items)
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
    
    # Update part request status - only use fields that exist
    parts_request.update(
      status: 'approved',
      in_stock: true
    )
    
    # Also update the timestamp if the field exists
    if parts_request.respond_to?(:approved_at)
      parts_request.update_column(:approved_at, Time.current)
    end
    
    # Optionally deduct from inventory if we're consuming the part
    if parts_request.part && parts_request.part.current_stock >= parts_request.quantity
      parts_request.part.update(
        current_stock: parts_request.part.current_stock - parts_request.quantity
      )
      
      # Create inventory transaction record
      InventoryTransaction.create!(
        inventory_item: parts_request.part,
        quantity: -parts_request.quantity,
        transaction_type: 'consumption',
        reference: parts_request,
        notes: "Consumed for job ##{parts_request.inspection_job_id}",
        user_id: current_user.id
      )
    end
    
    flash[:notice] = "Part approved and allocated to job ##{parts_request.inspection_job_id}"
    redirect_to vmcott_inventory_manager_dashboard_path
  rescue => e
    Rails.logger.error "Error in mark_in_stock: #{e.message}"
    flash[:alert] = "Failed to approve part: #{e.message}"
    redirect_to vmcott_inventory_manager_dashboard_path
  end

  # Send out-of-stock part to procurement for ordering
  def send_to_procurement
    parts_request = PartsRequest.find(params[:id])
    
    # Update part request status - use the correct field names
    update_params = {
      status: 'parts_coordinator_notified'
    }
    
    # Add timestamp if the field exists
    if parts_request.respond_to?(:sent_to_procurement_at)
      update_params[:sent_to_procurement_at] = Time.current
    end
    
    if parts_request.respond_to?(:notified_parts_coordinator_at)
      update_params[:notified_parts_coordinator_at] = Time.current
    end
    
    parts_request.update(update_params)
    
    flash[:notice] = "Part sent to procurement team for ordering"
    redirect_to vmcott_inventory_manager_dashboard_path
  rescue => e
    Rails.logger.error "Error in send_to_procurement: #{e.message}"
    flash[:alert] = "Failed to send to procurement: #{e.message}"
    redirect_to vmcott_inventory_manager_dashboard_path
  end

  # Pass completed job to workshop when all parts are ready
  def pass_to_workshop
    inspection = Inspection.find(params[:id])
    
    # Verify all parts are actually available
    if inspection.all_parts_available?
      inspection.update(
        status: 'ready_for_workshop',
        passed_to_workshop_at: Time.current,
        passed_to_workshop_by_id: current_user.id
      )
      
      # Notify mechanics
      notify_mechanics_workshop_ready(inspection)
      
      flash[:notice] = "Job passed to workshop. Mechanics notified."
    else
      flash[:alert] = "Cannot pass to workshop - not all parts are available yet."
    end
    
    redirect_to vmcott_inventory_manager_dashboard_path
  rescue => e
    Rails.logger.error "Error in pass_to_workshop: #{e.message}"
    flash[:alert] = "Failed to pass to workshop: #{e.message}"
    redirect_to vmcott_inventory_manager_dashboard_path
  end

  # Mark purchase order as ordered
  def mark_po_ordered
    purchase_order = PurchaseOrder.find(params[:id])
    purchase_order.update(status: 'ordered', ordered_at: Time.current)
    
    # Update associated parts requests
    purchase_order.parts_requests.each do |pr|
      pr.update(status: 'parts_ordered')
      
      # Update ordered_at if the field exists
      if pr.respond_to?(:ordered_at)
        pr.update_column(:ordered_at, Time.current)
      end
    end
    
    redirect_to vmcott_inventory_manager_dashboard_path, notice: "PO marked as ordered"
  rescue => e
    Rails.logger.error "Error in mark_po_ordered: #{e.message}"
    flash[:alert] = "Failed to mark PO as ordered: #{e.message}"
    redirect_to vmcott_inventory_manager_dashboard_path
  end

  # 🔥 UPDATED: Mark purchase order as received and update inventory with supervisor notification
  def mark_po_received
    purchase_order = PurchaseOrder.find(params[:id])
    purchase_order.update(status: 'received', received_at: Time.current)
    
    # Update all associated parts requests and inventory
    received_count = 0
    supervisor_notified = false
    
    purchase_order.parts_requests.each do |pr|
      update_params = { status: 'parts_received' }
      
      # Add timestamp if the field exists
      if pr.respond_to?(:parts_received_at)
        update_params[:parts_received_at] = Time.current
      end
      
      pr.update(update_params)
      received_count += 1
      
      # Update inventory stock levels
      if pr.part
        pr.part.update(current_stock: pr.part.current_stock + pr.quantity)
        
        # Create inventory transaction record
        InventoryTransaction.create!(
          inventory_item: pr.part,
          quantity: pr.quantity,
          transaction_type: 'receipt',
          reference: purchase_order,
          notes: "Received via PO ##{purchase_order.po_number}",
          user_id: current_user.id
        )
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
      
      # Check if all parts for this inspection are now available
      inspection = pr.inspection
      if inspection && inspection.all_parts_available?
        inspection.update(
          status: 'ready_for_workshop',
          parts_ready_at: Time.current
        )
        notify_mechanics_workshop_ready(inspection)
      end
    end
    
    notice = "PO marked as received. #{received_count} parts updated in inventory."
    notice += " Supervisor notified." if supervisor_notified
    
    redirect_to vmcott_inventory_manager_dashboard_path, notice: notice
  rescue => e
    Rails.logger.error "Error in mark_po_received: #{e.message}"
    flash[:alert] = "Failed to mark PO as received: #{e.message}"
    redirect_to vmcott_inventory_manager_dashboard_path
  end

  # Receive parts from an order (alternative endpoint)
  def receive_parts
    purchase_order = PurchaseOrder.find(params[:purchase_order_id])
    parts_request = PartsRequest.find(params[:parts_request_id])
    
    purchase_order.update(status: 'received', received_at: Time.current) if purchase_order.status != 'received'
    
    update_params = { status: 'parts_received' }
    
    # Add timestamp if the field exists
    if parts_request.respond_to?(:parts_received_at)
      update_params[:parts_received_at] = Time.current
    end
    
    parts_request.update(update_params)
    
    # Update inventory
    if parts_request.part
      parts_request.part.update(current_stock: parts_request.part.current_stock + parts_request.quantity)
      
      InventoryTransaction.create!(
        inventory_item: parts_request.part,
        quantity: parts_request.quantity,
        transaction_type: 'receipt',
        reference: purchase_order,
        notes: "Received via PO ##{purchase_order.po_number}",
        user_id: current_user.id
      )
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
    
    # Check if inspection is now ready
    inspection = parts_request.inspection
    if inspection && inspection.all_parts_available?
      inspection.update(
        status: 'ready_for_workshop',
        parts_ready_at: Time.current
      )
      notify_mechanics_workshop_ready(inspection)
      flash[:notice] = "Parts received. All parts ready! Job passed to workshop. Supervisor notified."
    else
      flash[:notice] = "Parts marked as received. Supervisor notified."
    end
    
    redirect_to vmcott_inventory_manager_dashboard_path
  rescue => e
    Rails.logger.error "Error in receive_parts: #{e.message}"
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
      update_params = {
        status: 'parts_coordinator_notified'
      }
      
      # Add timestamp if the field exists
      if parts_request.respond_to?(:sent_to_procurement_at)
        update_params[:sent_to_procurement_at] = Time.current
      end
      
      if parts_request.respond_to?(:notified_parts_coordinator_at)
        update_params[:notified_parts_coordinator_at] = Time.current
      end
      
      parts_request.update(update_params)
      
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

  # 🔥 NEW: Get low stock parts for reordering
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

  # 🔥 NEW: Generate reorder suggestions
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
    # Calculate average delivery time for completed orders
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
      Notification.create!(
        title: "🚗 Vehicle Ready for Repair",
        message: "All parts for #{inspection.vehicle.license_plate} (#{inspection.vehicle.make} #{inspection.vehicle.model}) are available. Ready for workshop.",
        link: vmcott_mechanic_job_path(inspection.id),
        user_id: mechanic_ids,
        notifiable_type: 'Inspection',
        notifiable_id: inspection.id,
        notification_type: 'success'
      )
    end
    
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