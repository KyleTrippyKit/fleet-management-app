# app/controllers/vmcott/parts_coordinator/dashboard_controller.rb
class Vmcott::PartsCoordinator::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_parts_coordinator
  before_action :set_part, only: [:create_rfq, :create_and_send_rfq]

  def index
    @pending_parts = PartsRequest.includes(:inspection, :part)
                                 .where(status: 'pending')
                                 .order(created_at: :asc)
    
    @pending_billing = PartsRequest.includes(:inspection, :part)
                                   .where(status: 'billing_notified')
                                   .order(created_at: :asc)
    
    @pending_finance = PartsRequest.includes(:inspection, :part)
                                   .where(status: 'quotations_received')
                                   .order(created_at: :asc)
    
    @purchase_orders_created = PartsRequest.includes(:inspection, :part, :purchase_order)
                                           .where(status: 'purchase_order_created')
                                           .order(created_at: :asc)
    
    @parts_received = Inspection.includes(:vehicle, :parts_requests)
                                .where(parts_requests: { status: 'parts_received' })
                                .distinct
                                .order(updated_at: :desc)
    
    @active_rfqs = VendorRfq.where(status: ['draft', 'sent'])
                            .includes(:vendor_quotations)
                            .order(created_at: :desc)
    
    @low_stock_parts = Part.where('current_stock <= reorder_point')
                           .order(current_stock: :asc)
                           .limit(20)
    
    @pending_receipts = PurchaseOrder.where(vendor: 'VMCOTT', status: 'ordered')
                                     .where.not(id: VendorInvoice.pluck(:purchase_order_id))
  end

  def create_rfq
    # Check if part exists
    unless @part
      flash[:alert] = "Part not found"
      redirect_to vmcott_parts_coordinator_dashboard_path and return
    end
    
    @parts_request = PartsRequest.find_by(id: params[:parts_request_id])
    @suppliers = Supplier.where(is_active: true).order(:name)
  end

  def create_and_send_rfq
    unless @part
      flash[:alert] = "Part not found"
      redirect_to vmcott_parts_coordinator_dashboard_path and return
    end

    # Validate that at least one supplier is selected
    if params[:supplier_ids].blank?
      flash[:alert] = "Please select at least one supplier."
      redirect_to vmcott_parts_coordinator_new_rfq_path(@part, parts_request_id: params[:parts_request_id]) and return
    end
    
    ActiveRecord::Base.transaction do
      # Create RFQ
      @rfq = VendorRfq.create!(
        rfq_number: generate_rfq_number,
        created_by: current_user,
        processing_agency: current_user.agency,
        status: 'sent',
        sent_date: Date.current,
        due_date: params[:due_date],
        notes: params[:notes]
      )
      
      # Create RFQ item
      @rfq.vendor_rfq_items.create!(
        part: @part,
        quantity: params[:quantity] || 1,
        description: @part.description,
        unit_of_measure: @part.unit_of_measure
      )
      
      # Create vendor quotations for selected suppliers
      params[:supplier_ids].each do |supplier_id|
        @rfq.vendor_quotations.create!(
          supplier_id: supplier_id,
          status: 'draft'
        )
      end
      
      # Update parts request if provided
      if params[:parts_request_id].present?
        parts_request = PartsRequest.find(params[:parts_request_id])
        parts_request.update!(
          status: 'rfq_sent',
          notified_billing_at: Time.current
        )
      end
      
      # Send emails (in background)
      @rfq.vendor_quotations.each do |quote|
        VendorRfqMailer.send_to_supplier(quote).deliver_later if defined?(VendorRfqMailer)
      end
    end
    
    redirect_to vmcott_parts_coordinator_dashboard_path, 
                notice: "RFQ ##{@rfq.rfq_number} sent to #{@rfq.vendor_quotations.count} suppliers."
                
  rescue ActiveRecord::RecordInvalid => e
    flash[:alert] = "Error creating RFQ: #{e.message}"
    redirect_to vmcott_parts_coordinator_new_rfq_path(@part, parts_request_id: params[:parts_request_id])
  end

  def send_rfq
    @rfq = VendorRfq.find(params[:id])
    
    # Update RFQ with form data
    @rfq.update(
      status: 'sent',
      sent_date: Date.current,
      due_date: params[:due_date],
      notes: params[:notes]
    )
    
    # Create vendor quotations for selected suppliers
    if params[:supplier_ids].present?
      params[:supplier_ids].each do |supplier_id|
        @rfq.vendor_quotations.create!(
          supplier_id: supplier_id,
          status: 'draft'
        )
      end
    end
    
    # Send emails
    @rfq.vendor_quotations.each do |quote|
      VendorRfqMailer.send_to_supplier(quote).deliver_later if defined?(VendorRfqMailer)
    end
    
    redirect_to vmcott_parts_coordinator_dashboard_path, notice: "RFQ sent to suppliers"
  end

  def compare_quotations
    @rfq = VendorRfq.find(params[:id])
    @quotations = @rfq.vendor_quotations.where(status: 'received')
    
    # Get part info from the first RFQ item
    @part = @rfq.vendor_rfq_items.first&.part
    
    unless @part
      flash[:alert] = "No parts found for this RFQ"
      redirect_to vmcott_parts_coordinator_dashboard_path and return
    end
    
    @lowest_price = @quotations.map(&:total_amount).compact.min || 0
    @most_frequent_vendor = find_most_frequent_vendor(@part)
  end

  def accept_quotation
    @quote = VendorQuotation.find(params[:id])
    @rfq = @quote.vendor_rfq
    
    begin
      po = @rfq.award_to!(quotation: @quote, user: current_user)
      
      # Update parts request
      if params[:parts_request_id].present?
        parts_request = PartsRequest.find(params[:parts_request_id])
        parts_request.update!(
          status: 'purchase_order_created',
          purchase_order: po
        )
      end
      
      redirect_to purchase_order_path(po), notice: "Quotation accepted. Purchase Order ##{po.po_number} created."
    rescue => e
      redirect_to vmcott_parts_coordinator_compare_rfq_path(@rfq), alert: "Error: #{e.message}"
    end
  end

  def receive_parts
    @po = PurchaseOrder.find(params[:purchase_order_id])
    
    ActiveRecord::Base.transaction do
      # Create vendor invoice
      invoice = VendorInvoice.create!(
        supplier: @po.supplier,
        invoice_number: params[:invoice_number],
        invoice_date: params[:invoice_date] || Date.current,
        amount: @po.amount,
        status: 'pending',
        purchase_order: @po,
        user: current_user
      )
      
      # Create invoice items and update stock
      @po.purchase_order_items.each do |item|
        next unless item.part.present?
        
        VendorInvoiceItem.create!(
          vendor_invoice: invoice,
          part: item.part,
          quantity: item.quantity,
          unit_price: item.unit_price,
          total_price: item.unit_price * item.quantity
        )
        
        # Update stock
        item.part.update!(
          current_stock: item.part.current_stock + item.quantity
        )
      end
      
      # Update PO status
      @po.update!(
        status: 'received',
        received_at: Time.current
      )
      
      # Update parts requests
      PartsRequest.where(purchase_order: @po).update_all(
        status: 'parts_received',
        parts_received_at: Time.current,
        vendor_invoice: invoice
      )
      
      # Notify inspections
      @po.parts_requests.each do |pr|
        pr.inspection.check_parts_availability! if pr.inspection.respond_to?(:check_parts_availability!)
      end
    end
    
    redirect_to vmcott_parts_coordinator_dashboard_path, notice: "Parts received and inventory updated."
  rescue => e
    redirect_to vmcott_parts_coordinator_dashboard_path, alert: "Error receiving parts: #{e.message}"
  end

  # Mark part as in-stock and pass inspection
  def mark_in_stock
    parts_request = PartsRequest.find(params[:id])
    
    if parts_request.in_stock?
      parts_request.update!(status: 'approved')
      parts_request.inspection.check_parts_availability! if parts_request.inspection.respond_to?(:check_parts_availability!)
      redirect_to vmcott_parts_coordinator_dashboard_path, notice: "Part marked as in-stock."
    else
      redirect_to vmcott_parts_coordinator_dashboard_path, alert: "Part is not in stock."
    end
  end

  # Send to billing to create RFQ
  def send_to_billing
    parts_request = PartsRequest.find(params[:id])
    parts_request.notify_billing! if parts_request.respond_to?(:notify_billing!)
    redirect_to vmcott_parts_coordinator_dashboard_path, notice: "Sent to billing team for RFQ."
  end

  # Pass inspection to workshop when all parts are received
  def pass_to_workshop
    inspection = Inspection.find(params[:id])
    
    inspection.update!(
      status: 'approved_for_repair',
      mechanic_notified_at: Time.current
    )
    
    # Notify mechanics (if you have this job)
    # MechanicNotificationJob.perform_later(inspection.id) if defined?(MechanicNotificationJob)
    
    redirect_to vmcott_parts_coordinator_dashboard_path, notice: "Inspection passed to workshop. Mechanics notified."
  end

  private

  def set_part
    @part = Part.find_by(id: params[:part_id])
    unless @part
      flash[:alert] = "Part not found"
      redirect_to vmcott_parts_coordinator_dashboard_path and return
    end
  end

  def require_parts_coordinator
    unless current_user.parts_coordinator? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Parts Coordinator privileges required."
    end
  end

  def generate_rfq_number
    "RFQ-#{Date.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
  end

  def find_most_frequent_vendor(part)
    # Find supplier with most previous purchases for this part
    PurchaseOrder.joins(:purchase_order_items)
                .where(purchase_order_items: { part_id: part.id })
                .group(:vendor)
                .count
                .max_by { |_, count| count }
                &.first
  end
end