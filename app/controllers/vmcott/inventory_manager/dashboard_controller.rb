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
      pending_review: PartsRequest.where(status: ['requested', 'approved']).count,
      with_procurement: PartsRequest.where(status: 'needs_order').count,
      ordered: PartsRequest.where(status: 'ordered').count,
      received_awaiting_confirmation: PartsRequest.where(status: 'received').count,
      confirmed: PartsRequest.where(status: 'confirmed').count,
      low_stock: Part.where('current_stock <= reorder_point').count
    }

    # 🔥 Pending parts - needs review
    @pending_parts = PartsRequest
      .includes(inspection: :vehicle, part: [], inspection_job: [])
      .where(status: ['requested', 'approved'])
      .order(created_at: :desc)
      .limit(20)

    # 🔥 With Procurement - needs ordering
    @pending_procurement = PartsRequest
      .includes(inspection: :vehicle, part: [])
      .where(status: 'needs_order')
      .order(updated_at: :desc)
      .limit(20)

    # 🔥 Ordered - Awaiting delivery
    @ordered_requests = PartsRequest
      .includes(:purchase_order, :part, inspection: :vehicle)
      .where(status: 'ordered')
      .order(updated_at: :desc)
      .limit(20)
    
    # 🔥🔥🔥 RECEIVED - Awaiting Confirmation (MUST be confirmed before quotation)
    @received_awaiting_confirmation = PartsRequest
      .includes(inspection: :vehicle, part: [])
      .where(status: 'received')
      .order(updated_at: :desc)
      .limit(20)
    
    # 🔥 Confirmed parts (ready for quotation)
    @confirmed_parts = PartsRequest
      .includes(inspection: :vehicle, part: [])
      .where(status: 'confirmed')
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

    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    render 'vmcott/inventory_manager/dashboard/index'
  end

  # Approve and allocate in-stock part to job (for in-stock parts only)
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
        
        # Notify mechanic that part is available
        if parts_request.inspection_job&.assigned_mechanic
          Notification.create!(
            user: parts_request.inspection_job.assigned_mechanic,
            title: "🔧 Part Ready for Pickup",
            message: "#{parts_request.quantity}x #{parts_request.part&.name || parts_request.custom_part_name} has been issued for your job.",
            link: vmcott_mechanic_job_path(parts_request.inspection_job),
            notification_type: 'success',
            notifiable: parts_request
          )
        end
      end
    end
    
    flash[:notice] = "✓ Part approved and issued to job"
    redirect_to vmcott_inventory_manager_dashboard_path
    
  rescue => e
    Rails.logger.error "Error in mark_in_stock: #{e.message}"
    flash[:alert] = "Failed to approve part: #{e.message}"
    redirect_to vmcott_inventory_manager_dashboard_path
  end

  # Send out-of-stock part to procurement for ordering
  def send_to_procurement
    parts_request = PartsRequest.find(params[:id])
    
    parts_request.update!(
      status: 'needs_order'
    )
    
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
    
    # Notify workshop supervisor
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
      
      purchase_order.parts_requests.each do |pr|
        pr.update!(
          status: 'ordered'
        )
        
        # Notify requester
        if pr.requested_by.present?
          Notification.create!(
            user: pr.requested_by,
            title: "📦 Parts Ordered",
            message: "#{pr.quantity}x #{pr.part_name} has been ordered. PO ##{purchase_order.po_number}",
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

  # 🔥 UPDATED: Mark purchase order as received (sets to 'received', NOT confirmed)
  def mark_po_received
    purchase_order = PurchaseOrder.find(params[:id])
    
    ActiveRecord::Base.transaction do
      purchase_order.update(status: 'received', received_at: Time.current)
      
      purchase_order.parts_requests.each do |pr|
        # 🔥 Set to 'received' - NOT confirmed yet! Quotation cannot be created until confirmed.
        pr.update!(
          status: 'received'
        )
        
        # Update inventory stock levels
        if pr.part
          old_stock = pr.part.current_stock
          new_stock = old_stock + pr.quantity
          pr.part.update!(current_stock: new_stock)
          
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
        
        # Notify requester that parts are received (but NOT confirmed yet)
        if pr.requested_by.present?
          Notification.create!(
            user: pr.requested_by,
            title: "📦 Parts Received - Awaiting Confirmation",
            message: "#{pr.quantity}x #{pr.part_name} has been received. Waiting for inventory confirmation.",
            link: vmcott_mechanic_dashboard_path,
            notification_type: 'info',
            notifiable: pr
          )
        end
        
        # Notify supervisor that parts are received (but NOT confirmed yet)
        if pr.inspection && pr.inspection.supervisor.present?
          Notification.create!(
            user: pr.inspection.supervisor,
            title: "📦 Parts Received - Awaiting Confirmation",
            message: "#{pr.quantity}x #{pr.part_name} has been received for #{pr.inspection.vehicle.license_plate}. Waiting for inventory confirmation before quotation.",
            link: vmcott_workshop_supervisor_dashboard_path,
            notification_type: 'info',
            notifiable: pr
          )
        end
      end
      
      flash[:notice] = "✓ PO marked as received. Parts need confirmation before quotation can be created."
    end
    
    redirect_to vmcott_inventory_manager_dashboard_path
    
  rescue => e
    Rails.logger.error "Error in mark_po_received: #{e.message}"
    flash[:alert] = "Failed to mark PO as received: #{e.message}"
    redirect_to vmcott_inventory_manager_dashboard_path
  end

  # 🔥 NEW: Confirm a single part (mark as ready for quotation)
  def confirm_part
    parts_request = PartsRequest.find(params[:id])
    
    ActiveRecord::Base.transaction do
      # Update to confirmed status - ONLY update status column
      parts_request.update!(
        status: 'confirmed'
      )
      
      # Check if all parts for this inspection are now confirmed
      inspection = parts_request.inspection
      if inspection && inspection.all_parts_confirmed?
        inspection.update!(status: 'parts_confirmed')
        
        # Notify supervisor that all parts are confirmed
        if inspection.supervisor.present?
          Notification.create!(
            user: inspection.supervisor,
            title: "✅ All Parts Confirmed",
            message: "All parts for #{inspection.vehicle.license_plate} are confirmed. Ready to create quotation.",
            link: vmcott_workshop_supervisor_quotation_creation_path(inspection),
            notification_type: 'success',
            notifiable: inspection
          )
        end
      end
      
      # Notify requester
      if parts_request.requested_by.present?
        Notification.create!(
          user: parts_request.requested_by,
          title: "✅ Part Confirmed",
          message: "#{parts_request.quantity}x #{parts_request.part_name} has been confirmed and is ready for quotation.",
          link: vmcott_mechanic_dashboard_path,
          notification_type: 'success',
          notifiable: parts_request
        )
      end
    end
    
    flash[:notice] = "✅ Part confirmed! Ready for quotation."
    redirect_to vmcott_inventory_manager_dashboard_path
    
  rescue => e
    Rails.logger.error "Error confirming part: #{e.message}"
    flash[:alert] = "Error confirming part: #{e.message}"
    redirect_to vmcott_inventory_manager_dashboard_path
  end

  # 🔥 NEW: Confirm all parts for an inspection
  def confirm_all_parts
    inspection = Inspection.find(params[:inspection_id])
    confirmed_count = 0
    
    ActiveRecord::Base.transaction do
      inspection.parts_requests.where(status: 'received').each do |pr|
        pr.update!(status: 'confirmed')
        confirmed_count += 1
      end
      
      if confirmed_count > 0
        inspection.update!(status: 'parts_confirmed')
        
        # Notify supervisor
        if inspection.supervisor.present?
          Notification.create!(
            user: inspection.supervisor,
            title: "✅ All Parts Confirmed",
            message: "All parts for #{inspection.vehicle.license_plate} are confirmed. Ready to create quotation.",
            link: vmcott_workshop_supervisor_quotation_creation_path(inspection),
            notification_type: 'success',
            notifiable: inspection
          )
        end
      end
    end
    
    flash[:notice] = "✅ #{confirmed_count} part(s) confirmed. Ready for quotation."
    redirect_to vmcott_inventory_manager_dashboard_path
    
  rescue => e
    Rails.logger.error "Error confirming all parts: #{e.message}"
    flash[:alert] = "Error confirming parts: #{e.message}"
    redirect_to vmcott_inventory_manager_dashboard_path
  end

  # Receive parts from an order (alternative endpoint)
  def receive_parts
    purchase_order = PurchaseOrder.find(params[:purchase_order_id])
    parts_request = PartsRequest.find(params[:parts_request_id])
    
    ActiveRecord::Base.transaction do
      purchase_order.update(status: 'received', received_at: Time.current) if purchase_order.status != 'received'
      
      # 🔥 Set to 'received' - NOT confirmed
      parts_request.update!(
        status: 'received'
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
      end
      
      flash[:notice] = "✓ Parts marked as received. Please confirm them when ready for quotation."
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
      parts_request.update!(
        status: 'needs_order'
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
end