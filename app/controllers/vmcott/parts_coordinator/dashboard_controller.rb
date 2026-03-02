# app/controllers/vmcott/parts_coordinator/dashboard_controller.rb
class Vmcott::PartsCoordinator::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_parts_coordinator
  before_action :set_part, only: [:create_rfq, :create_and_send_rfq]
  before_action :ensure_can_mark_in_stock, only: [:mark_in_stock]
  before_action :ensure_can_send_to_billing, only: [:send_to_billing]

  def index
    # FIXED: Only show what parts coordinator needs to see
    @pending_requests = PartsRequest.includes(:inspection, :part, :inspection_job)
                                    .where(status: 'pending_parts_coordinator')
                                    .order(created_at: :asc)
    
    # In-stock parts ready for parts coordinator to process
    @in_stock_requests = PartsRequest.includes(:inspection, :part, :inspection_job)
                                     .where(status: 'pending_parts_coordinator', in_stock: true)
                                     .order(created_at: :asc)
    
    # Out of stock parts needing RFQ
    @out_of_stock_requests = PartsRequest.includes(:inspection, :part, :inspection_job)
                                         .where(status: 'pending_parts_coordinator', in_stock: false)
                                         .order(created_at: :asc)
    
    # Parts being processed (RFQ sent, waiting for quotes)
    @processing_requests = PartsRequest.includes(:inspection, :part, :inspection_job)
                                       .where(status: ['rfq_sent', 'quotations_received'])
                                       .order(created_at: :asc)
    
    # Parts ordered (PO created, waiting for delivery)
    @ordered_requests = PartsRequest.includes(:inspection, :part, :inspection_job, :purchase_order)
                                    .where(status: 'purchase_order_created')
                                    .order(created_at: :asc)
    
    # Parts received and ready for installation
    @received_requests = PartsRequest.includes(:inspection, :part, :inspection_job)
                                     .where(status: 'parts_received')
                                     .order(created_at: :asc)
    
    # Inspections ready for workshop (all parts received)
    @ready_for_workshop = Inspection.joins(:parts_requests)
                                    .where(parts_requests: { status: 'parts_received' })
                                    .where(status: 'parts_coordinator_review')
                                    .distinct
                                    .order(updated_at: :asc)
    
    # Active RFQs
    @active_rfqs = VendorRfq.where(status: ['draft', 'sent'])
                            .includes(:vendor_quotations)
                            .order(created_at: :desc)
                            .limit(10)
    
    # Low stock alerts
    @low_stock_parts = Part.where('current_stock <= reorder_point')
                           .order(current_stock: :asc)
                           .limit(20)
    
    # Pending receipts
    @pending_receipts = PurchaseOrder.where(status: 'ordered')
                                     .where.not(id: VendorInvoice.pluck(:purchase_order_id))
                                     .order(created_at: :desc)
                                     .limit(10)
    
    # Statistics
    @stats = {
      pending_count: @pending_requests.count,
      in_stock_count: @in_stock_requests.count,
      out_of_stock_count: @out_of_stock_requests.count,
      processing_count: @processing_requests.count,
      ordered_count: @ordered_requests.count,
      received_count: @received_requests.count,
      ready_for_workshop_count: @ready_for_workshop.count
    }
  end

  # Mark part as in-stock (part is available in inventory)
  def mark_in_stock
    @parts_request = PartsRequest.find(params[:id])
    
    ActiveRecord::Base.transaction do
      @parts_request.update!(
        in_stock: true,
        processed_by: current_user.id,
        processed_at: Time.current
      )
      
      # Check if all parts for this inspection are now in stock
      inspection = @parts_request.inspection
      
      # If all parts are in stock, notify finance to create quotation
      if inspection.parts_requests.where(in_stock: false).none?
        notify_finance_for_quotation(inspection)
      end
      
      flash[:notice] = "Part marked as in-stock."
    end
    
    redirect_to vmcott_parts_coordinator_dashboard_path
  rescue => e
    redirect_to vmcott_parts_coordinator_dashboard_path, alert: "Error: #{e.message}"
  end

  # Send to billing to create RFQ (for out-of-stock parts)
  def send_to_billing
    @parts_request = PartsRequest.find(params[:id])
    
    # Create RFQ for billing team
    create_rfq_for_part(@parts_request)
    
    redirect_to vmcott_parts_coordinator_dashboard_path, 
                notice: "Part sent to billing team for RFQ creation."
  end

  # Create RFQ form
  def create_rfq
    @parts_request = PartsRequest.find_by(id: params[:parts_request_id])
    @suppliers = Supplier.where(is_active: true).order(:name)
  end

  # Create and send RFQ
  def create_and_send_rfq
    @parts_request = PartsRequest.find_by(id: params[:parts_request_id])
    
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
        due_date: params[:due_date] || 7.days.from_now,
        notes: params[:notes]
      )
      
      # Create RFQ item
      @rfq.vendor_rfq_items.create!(
        part: @part,
        quantity: @parts_request&.quantity || params[:quantity] || 1,
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
      
      # Update parts request
      if @parts_request.present?
        @parts_request.update!(
          status: 'rfq_sent',
          notified_billing_at: Time.current
        )
      end
      
      # Send emails (in background)
      @rfq.vendor_quotations.each do |quote|
        VendorRfqMailer.send_to_supplier(quote).deliver_later if defined?(VendorRfqMailer)
      end
      
      flash[:notice] = "RFQ ##{@rfq.rfq_number} sent to #{@rfq.vendor_quotations.count} suppliers."
    end
    
    redirect_to vmcott_parts_coordinator_dashboard_path
                
  rescue ActiveRecord::RecordInvalid => e
    flash[:alert] = "Error creating RFQ: #{e.message}"
    redirect_to vmcott_parts_coordinator_new_rfq_path(@part, parts_request_id: params[:parts_request_id])
  end

  # Send RFQ (for existing RFQs)
  def send_rfq
    @rfq = VendorRfq.find(params[:id])
    
    # Update RFQ with form data
    @rfq.update(
      status: 'sent',
      sent_date: Date.current,
      due_date: params[:due_date] || 7.days.from_now,
      notes: params[:notes]
    )
    
    # Create vendor quotations for selected suppliers if not already created
    if params[:supplier_ids].present?
      params[:supplier_ids].each do |supplier_id|
        @rfq.vendor_quotations.find_or_create_by!(
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

  # Compare quotations received
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

  # Accept quotation and create PO
  def accept_quotation
    @quote = VendorQuotation.find(params[:id])
    @rfq = @quote.vendor_rfq
    @parts_request = PartsRequest.find_by(id: params[:parts_request_id])
    
    begin
      # Create purchase order
      po = PurchaseOrder.create!(
        po_number: generate_po_number,
        supplier: @quote.supplier,
        vendor: @quote.supplier.name,
        amount: @quote.total_amount,
        status: 'approved',
        created_by: current_user,
        payment_terms: 'net_30',
        notes: "Created from RFQ #{@rfq.rfq_number}"
      )
      
      # Create PO items
      @quote.vendor_quotation_lines.each do |line|
        po.purchase_order_items.create!(
          part: line.part,
          description: line.description,
          quantity: line.quantity,
          unit_price: line.unit_price,
          total_price: line.total_price
        )
      end
      
      # Update RFQ
      @rfq.update!(
        status: 'awarded',
        awarded_vendor_quotation: @quote,
        awarded_at: Time.current
      )
      
      # Update parts request
      if @parts_request.present?
        @parts_request.update!(
          status: 'purchase_order_created',
          purchase_order: po,
          notified_billing_at: Time.current
        )
      end
      
      redirect_to purchase_order_path(po), notice: "Quotation accepted. Purchase Order ##{po.po_number} created."
    rescue => e
      redirect_to vmcott_parts_coordinator_compare_rfq_path(@rfq), alert: "Error: #{e.message}"
    end
  end

  # Receive parts (when they arrive)
  def receive_parts
    @po = PurchaseOrder.find(params[:purchase_order_id])
    @parts_request = PartsRequest.find_by(id: params[:parts_request_id]) if params[:parts_request_id].present?
    
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
      
      # Update parts request
      if @parts_request.present?
        @parts_request.update!(
          status: 'parts_received',
          parts_received_at: Time.current,
          vendor_invoice: invoice,
          in_stock: true
        )
        
        # Notify mechanic that parts are ready
        notify_mechanic_parts_ready(@parts_request)
        
        # Check if all parts for this inspection are now received
        inspection = @parts_request.inspection
        if inspection.parts_requests.where(status: ['pending_parts_coordinator', 'rfq_sent', 'purchase_order_created']).none?
          # All parts are received - update inspection status to approved_for_repair
          inspection.update!(status: 'approved_for_repair')
          notify_mechanics_work_ready(inspection)
        end
      end
      
      flash[:notice] = "Parts received and inventory updated."
    end
    
    redirect_to vmcott_parts_coordinator_dashboard_path
  rescue => e
    redirect_to vmcott_parts_coordinator_dashboard_path, alert: "Error receiving parts: #{e.message}"
  end

  # Pass inspection to workshop when all parts are received
  def pass_to_workshop
    inspection = Inspection.find(params[:id])
    
    # FIXED: Ensure all parts are received
    unless inspection.parts_requests.where(status: 'parts_received').count == inspection.parts_requests.count
      redirect_to vmcott_parts_coordinator_dashboard_path, alert: "Cannot pass to workshop: Not all parts have been received."
      return
    end
    
    inspection.update!(
      status: 'approved_for_repair',
      mechanic_notified_at: Time.current
    )
    
    # Notify mechanics
    notify_mechanics_work_ready(inspection)
    
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

  def ensure_can_mark_in_stock
    parts_request = PartsRequest.find_by(id: params[:id])
    return unless parts_request
    
    unless parts_request.status == 'pending_parts_coordinator'
      redirect_to vmcott_parts_coordinator_dashboard_path, 
                  alert: "This part request cannot be marked as in-stock at this stage."
      return false
    end
  end

  def ensure_can_send_to_billing
    parts_request = PartsRequest.find_by(id: params[:id])
    return unless parts_request
    
    unless parts_request.status == 'pending_parts_coordinator' && !parts_request.in_stock?
      redirect_to vmcott_parts_coordinator_dashboard_path, 
                  alert: "This part request cannot be sent to billing at this stage."
      return false
    end
  end

  def generate_rfq_number
    "RFQ-#{Date.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
  end

  def generate_po_number
    "PO-#{Date.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
  end

  def find_most_frequent_vendor(part)
    PurchaseOrder.joins(:purchase_order_items)
                .where(purchase_order_items: { part_id: part.id })
                .group(:vendor)
                .count
                .max_by { |_, count| count }
                &.first
  end

  def notify_finance_for_quotation(inspection)
    finance_ids = User.where(role: ['finance', 'billing']).pluck(:id)
    
    labor_cost = inspection.inspection_jobs.sum(&:estimated_labor_cost)
    parts_cost = inspection.parts_requests.where(in_stock: true).sum do |pr|
      pr.part&.cost_price.to_f * pr.quantity
    end
    
    total = labor_cost + parts_cost
    
    Notification.create!(
      title: "Create Quotation for Agency",
      message: "All parts are in stock for #{inspection.vehicle.license_plate}. " \
               "Labor: $#{'%.2f' % labor_cost}, Parts: $#{'%.2f' % parts_cost}, Total: $#{'%.2f' % total}",
      link: "/vmcott/finance/quotations/new_for_inspection/#{inspection.id}",
      user_id: finance_ids,
      notifiable_type: 'Inspection',
      notifiable_id: inspection.id
    )
  rescue => e
    Rails.logger.error "Failed to create notification: #{e.message}"
  end

  def create_rfq_for_part(parts_request)
    parts_request.update!(
      status: 'rfq_sent',
      sent_to_billing_at: Time.current
    )
    
    rfq = VendorRfq.create!(
      rfq_number: generate_rfq_number,
      created_by: current_user,
      processing_agency: current_user.agency,
      status: 'draft',
      notes: "Auto-created from parts request ##{parts_request.id}"
    )
    
    rfq.vendor_rfq_items.create!(
      part: parts_request.part,
      quantity: parts_request.quantity,
      description: parts_request.part&.description || parts_request.custom_part_name,
      unit_of_measure: parts_request.part&.unit_of_measure || 'each'
    )
    
    billing_ids = User.where(role: 'billing').pluck(:id)
    Notification.create!(
      title: "RFQ Ready for Suppliers",
      message: "Please send RFQ for #{parts_request.part&.name || parts_request.custom_part_name} to suppliers.",
      link: "/vmcott/billing/new_rfq/#{rfq.id}",
      user_id: billing_ids,
      notifiable_type: 'VendorRfq',
      notifiable_id: rfq.id
    )
  end

  def notify_mechanic_parts_ready(parts_request)
    mechanic_id = parts_request.inspection_job&.assigned_mechanic_id
    return unless mechanic_id.present?
    
    Notification.create!(
      title: "Parts Ready for Installation",
      message: "Parts for job '#{parts_request.inspection_job.description}' have arrived and are ready.",
      link: "/vmcott/mechanic/job/#{parts_request.inspection_job_id}",
      user_id: mechanic_id,
      notifiable_type: 'PartsRequest',
      notifiable_id: parts_request.id
    )
  end

  def notify_mechanics_work_ready(inspection)
    mechanic_ids = User.where(role: 'mechanic').pluck(:id)
    Notification.create!(
      title: "Work Ready to Start",
      message: "All parts for #{inspection.vehicle.license_plate} are available. Work can now begin.",
      link: "/vmcott/mechanic/dashboard",
      user_id: mechanic_ids,
      notifiable_type: 'Inspection',
      notifiable_id: inspection.id
    )
  end
end