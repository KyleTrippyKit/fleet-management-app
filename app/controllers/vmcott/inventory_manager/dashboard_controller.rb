class Vmcott::InventoryManager::DashboardController < ApplicationController
  # Skip the dashboard caching for this controller - THIS IS THE FIX!
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
      ready_for_workshop_count: Inspection.where(status: 'ready_for_workshop').count
    }

    # Pending parts (Tab 1)
    @pending_parts = PartsRequest.includes(inspection: :vehicle, part: [])
                                  .where(status: 'pending')
                                  .order(created_at: :desc)
                                  .limit(20)

    # With Procurement (Tab 2)
    @pending_procurement = PartsRequest.includes(inspection: :vehicle)
                                        .where(status: 'parts_coordinator_notified')
                                        .order(updated_at: :desc)
                                        .limit(20)

    # Finance Review (Tab 3)
    @pending_finance = PartsRequest.includes(inspection: :vehicle)
                                    .where(status: 'finance_review')
                                    .order(updated_at: :desc)
                                    .limit(20)

    # Ordered (Tab 4)
    @ordered_requests = PartsRequest.includes(:purchase_order)
                                     .where(status: 'parts_ordered')
                                     .order(updated_at: :desc)
                                     .limit(20)

    # Received (Tab 5)
    @parts_received = PartsRequest.includes(inspection: :vehicle)
                                   .where(status: 'parts_received')
                                   .order(updated_at: :desc)
                                   .limit(20)
    
    # Ready for workshop (Tab 6)
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
    
    # Set headers to prevent caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    render 'vmcott/inventory_manager/dashboard/index'
  end

  # Core workflow actions
  def mark_in_stock
    parts_request = PartsRequest.find(params[:id])
    parts_request.update(status: 'parts_received', in_stock: true, parts_received_at: Time.current)
    
    # Check if ALL parts for this inspection are now ready
    inspection = parts_request.inspection
    if inspection && inspection.all_parts_available?
      inspection.update(
        status: 'ready_for_workshop',
        parts_ready_at: Time.current
      )
      
      # Notify mechanics that job is ready
      notify_mechanics_workshop_ready(inspection)
      
      flash[:notice] = "Part marked as in stock. All parts ready! Job passed to workshop."
    else
      flash[:notice] = "Part marked as in stock. Waiting for remaining parts."
    end
    
    redirect_to vmcott_inventory_manager_dashboard_path
  end

  def send_to_procurement
    parts_request = PartsRequest.find(params[:id])
    parts_request.update(
      status: 'parts_coordinator_notified', 
      sent_to_procurement_at: Time.current
    )
    redirect_to vmcott_inventory_manager_dashboard_path, notice: "Part sent to procurement team"
  end

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
  end

  def mark_po_ordered
    purchase_order = PurchaseOrder.find(params[:id])
    purchase_order.update(status: 'ordered', ordered_at: Time.current)
    
    # Update associated parts requests
    purchase_order.parts_requests.each do |pr|
      pr.update(status: 'parts_ordered')
    end
    
    redirect_to vmcott_inventory_manager_dashboard_path, notice: "PO marked as ordered"
  end

  def mark_po_received
    purchase_order = PurchaseOrder.find(params[:id])
    purchase_order.update(status: 'received', received_at: Time.current)
    
    # Update all associated parts requests to 'parts_received'
    received_count = 0
    purchase_order.parts_requests.each do |pr|
      pr.update(status: 'parts_received', parts_received_at: Time.current)
      received_count += 1
      
      # Check if inspection is now ready
      inspection = pr.inspection
      if inspection && inspection.all_parts_available?
        inspection.update(
          status: 'ready_for_workshop',
          parts_ready_at: Time.current
        )
        notify_mechanics_workshop_ready(inspection)
      end
    end
    
    redirect_to vmcott_inventory_manager_dashboard_path, 
                notice: "PO marked as received. #{received_count} parts updated."
  end

  def create_rfq
    parts_request = PartsRequest.find(params[:parts_request_id])
    
    # Get the part and its unit of measure
    part = parts_request.part
    unit_of_measure = part&.unit_of_measure || 'each'
    
    # Generate a unique RFQ number
    rfq_number = generate_rfq_number
    
    # Create a new RFQ
    vendor_rfq = VendorRfq.new(
      rfq_number: rfq_number,
      processing_agency_id: current_user.agency_id,
      status: 'draft',
      notes: "Created from parts request ##{parts_request.id} for #{part&.name || parts_request.custom_part_name}"
    )
    
    # Add the part to RFQ items with unit of measure
    vendor_rfq.vendor_rfq_items.build(
      part_id: parts_request.part_id,
      quantity: parts_request.quantity,
      custom_part_name: parts_request.custom_part_name,
      description: part&.name,
      unit_of_measure: unit_of_measure
    )
    
    if vendor_rfq.save
      # Update parts request status
      parts_request.update(status: 'parts_coordinator_notified', sent_to_procurement_at: Time.current)
      
      # Redirect to the RFQ index page
      redirect_to vmcott_vendor_rfqs_path, notice: "RFQ ##{rfq_number} created successfully. You can now view and edit it from the list."
    else
      redirect_to vmcott_inventory_manager_dashboard_path, alert: "Failed to create RFQ: #{vendor_rfq.errors.full_messages.join(', ')}"
    end
  rescue => e
    redirect_to vmcott_inventory_manager_dashboard_path, alert: "Failed to create RFQ: #{e.message}"
  end

  def send_rfq
    rfq = VendorRfq.find(params[:id])
    rfq.update(status: 'sent', sent_date: Time.current)
    redirect_to vmcott_inventory_manager_dashboard_path, notice: "RFQ sent to suppliers"
  end

  def compare_quotations
    @rfq = VendorRfq.find(params[:id])
    @quotations = @rfq.vendor_quotations.includes(:supplier)
    
    # Disable caching for this action
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    render 'vmcott/inventory_manager/dashboard/compare_quotations'
  end

  def accept_quotation
    quotation = VendorQuotation.find(params[:id])
    quotation.update(status: 'accepted')
    
    # Update associated RFQ
    if quotation.vendor_rfq
      quotation.vendor_rfq.update(status: 'quotation_accepted')
    end
    
    redirect_to vmcott_inventory_manager_dashboard_path, notice: "Quotation accepted. Finance team will process."
  end

  def receive_parts
    purchase_order = PurchaseOrder.find(params[:purchase_order_id])
    parts_request = PartsRequest.find(params[:parts_request_id])
    
    purchase_order.update(status: 'received', received_at: Time.current)
    parts_request.update(status: 'parts_received', parts_received_at: Time.current)
    
    # Check if inspection is now ready
    inspection = parts_request.inspection
    if inspection && inspection.all_parts_available?
      inspection.update(
        status: 'ready_for_workshop',
        parts_ready_at: Time.current
      )
      notify_mechanics_workshop_ready(inspection)
      flash[:notice] = "Parts received. All parts ready! Job passed to workshop."
    else
      flash[:notice] = "Parts marked as received."
    end
    
    redirect_to vmcott_inventory_manager_dashboard_path
  end

  private

  def require_inventory_manager
    unless current_user.inventory_manager? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Inventory Manager access only."
    end
  end
  
  # Add this method to disable caching for all actions
  def disable_caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end
  
  # Generate a unique RFQ number
  def generate_rfq_number
    # Format: RFQ-YYYYMMDD-XXXX
    prefix = "RFQ-#{Time.current.strftime('%Y%m%d')}"
    
    # Find the next sequential number for today
    today_rfqs = VendorRfq.where("rfq_number LIKE ?", "#{prefix}-%")
    if today_rfqs.any?
      last_number = today_rfqs.order(:rfq_number).last.rfq_number.split('-').last.to_i
      next_number = last_number + 1
    else
      next_number = 1
    end
    
    "#{prefix}-#{next_number.to_s.rjust(4, '0')}"
  end
  
  # Helper method to notify mechanics when job is ready
  def notify_mechanics_workshop_ready(inspection)
    mechanic_ids = User.where(role: 'mechanic').pluck(:id)
    
    if mechanic_ids.any?
      Notification.create!(
        title: "🚗 Vehicle Ready for Repair",
        message: "All parts for #{inspection.vehicle.license_plate} (#{inspection.vehicle.make} #{inspection.vehicle.model}) are available. Ready for workshop.",
        link: vmcott_mechanic_job_path(inspection.id),
        user_id: mechanic_ids,
        notifiable_type: 'Inspection',
        notifiable_id: inspection.id
      )
    end
    
    # Also create a vehicle status update
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