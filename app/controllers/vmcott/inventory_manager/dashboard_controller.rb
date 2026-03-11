# app/controllers/vmcott/inventory_manager/dashboard_controller.rb
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
      pending_procurement: PartsRequest.where(status: 'procurement_notified').count,
      pending_finance: PartsRequest.where(status: 'finance_review').count,
      ordered_count: PurchaseOrder.where(status: 'ordered').count,
      parts_received: PartsRequest.where(status: 'parts_received').count,
      low_stock_count: Part.where('current_stock <= reorder_point').count,
      in_stock_count: Part.where('current_stock > reorder_point').count,
      out_of_stock_count: Part.where('current_stock <= 0').count,
      approved_po_count: PurchaseOrder.where(status: 'approved').count,
      ordered_po_count: PurchaseOrder.where(status: 'ordered').count
    }

    # Pending parts (Tab 1)
    @pending_parts = PartsRequest.includes(inspection: :vehicle, part: [])
                                  .where(status: 'pending')
                                  .order(created_at: :desc)
                                  .limit(20)

    # With Procurement (Tab 2)
    @pending_procurement = PartsRequest.includes(inspection: :vehicle)
                                        .where(status: 'procurement_notified')
                                        .order(updated_at: :desc)
                                        .limit(20)

    # Finance Review (Tab 3)
    @pending_finance = PartsRequest.includes(inspection: :vehicle)
                                    .where(status: 'finance_review')
                                    .order(updated_at: :desc)
                                    .limit(20)

    # Ordered (Tab 4)
    @ordered_requests = PartsRequest.includes(:purchase_order)
                                     .where(status: 'ordered')
                                     .order(updated_at: :desc)
                                     .limit(20)

    # Received (Tab 5)
    @parts_received = PartsRequest.includes(inspection: :vehicle)
                                   .where(status: 'parts_received')
                                   .order(updated_at: :desc)
                                   .limit(20)
    
    # Ready for workshop
    @ready_for_workshop = Inspection.where(status: 'parts_received')
                                    .includes(:vehicle)
                                    .order(updated_at: :desc)
                                    .limit(10)

    # Low stock alerts
    @low_stock_parts = Part.where('current_stock <= reorder_point')
                           .order(current_stock: :asc)
                           .limit(20)

    # Approved POs (Tab 6)
    @approved_pos = PurchaseOrder.includes(:purchase_order_items)
                                  .where(status: 'approved')
                                  .order(approved_at: :desc)
                                  .limit(10)

    # Ordered POs (Tab 6)
    @ordered_pos = PurchaseOrder.includes(:purchase_order_items)
                                 .where(status: 'ordered')
                                 .order(ordered_at: :desc)
                                 .limit(10)
    
    # Set headers to prevent caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end

  # Core workflow actions
  def mark_in_stock
    parts_request = PartsRequest.find(params[:id])
    parts_request.update(status: 'in_stock')
    redirect_to vmcott_inventory_manager_dashboard_path, notice: "Part marked as in stock"
  end

  def send_to_procurement
    parts_request = PartsRequest.find(params[:id])
    parts_request.update(status: 'procurement_notified', sent_to_procurement_at: Time.current)
    redirect_to vmcott_inventory_manager_dashboard_path, notice: "Part sent to procurement team"
  end

  def pass_to_workshop
    inspection = Inspection.find(params[:id])
    inspection.update(status: 'ready_for_workshop')
    redirect_to vmcott_inventory_manager_dashboard_path, notice: "Job passed to workshop"
  end

  def mark_po_ordered
    purchase_order = PurchaseOrder.find(params[:id])
    purchase_order.update(status: 'ordered', ordered_at: Time.current)
    redirect_to vmcott_inventory_manager_dashboard_path, notice: "PO marked as ordered"
  end

  def mark_po_received
    purchase_order = PurchaseOrder.find(params[:id])
    purchase_order.update(status: 'received', received_at: Time.current)
    redirect_to vmcott_inventory_manager_dashboard_path, notice: "PO marked as received"
  end

  def create_rfq
    parts_request = PartsRequest.find(params[:parts_request_id])
    # Logic to create RFQ
    redirect_to new_vendor_rfq_path(part_id: parts_request.part_id), notice: "Creating RFQ"
  end

  def send_rfq
    rfq = VendorRfq.find(params[:id])
    rfq.update(status: 'sent')
    redirect_to vmcott_inventory_manager_dashboard_path, notice: "RFQ sent to suppliers"
  end

  def compare_quotations
    @rfq = VendorRfq.find(params[:id])
    @quotations = @rfq.vendor_quotations.includes(:supplier)
    
    # Disable caching for this action
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    render 'compare_quotations'
  end

  def accept_quotation
    quotation = VendorQuotation.find(params[:id])
    quotation.update(status: 'accepted')
    redirect_to vmcott_inventory_manager_dashboard_path, notice: "Quotation accepted"
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
end