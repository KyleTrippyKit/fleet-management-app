# app/controllers/vmcott/parts_coordinator/dashboard_controller.rb
class Vmcott::PartsCoordinator::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_parts_coordinator
  
  def index
    @pending_parts = InspectionJob.pending
                                 .where('estimated_parts_cost > 0')
                                 .includes(:inspection => :vehicle) if defined?(InspectionJob)
    
    @active_rfqs = VendorRfq.where(status: ['draft', 'sent'])
                            .includes(:vendor_quotations) if defined?(VendorRfq)
    
    @low_stock_parts = Part.where('current_stock <= reorder_point')
                           .order('current_stock ASC')
                           .limit(10) if defined?(Part)
    
    @pending_receipts = PurchaseOrder.where(vendor: 'VMCOTT', status: 'ordered')
                                     .where.not(id: VendorInvoice.pluck(:purchase_order_id)) if defined?(PurchaseOrder) && defined?(VendorInvoice)
  end
  
  def create_rfq
    @part = Part.find(params[:part_id])
    
    # Just show the form - we'll create in create_and_send_rfq
    render :create_rfq
  end
  
  def create_and_send_rfq
    @part = Part.find(params[:part_id])
    
    # Validate that at least one supplier is selected
    if params[:supplier_ids].blank?
      flash[:alert] = "Please select at least one supplier."
      redirect_to vmcott_parts_coordinator_new_rfq_path(@part) and return
    end
    
    # Create and save the RFQ
    @rfq = VendorRfq.create!(
      rfq_number: generate_rfq_number,
      created_by_id: current_user.id,
      status: 'sent',
      sent_date: Date.current,
      due_date: params[:due_date],
      notes: params[:notes]
    )
    
    # Create RFQ item
    @rfq.vendor_rfq_items.create!(
      part: @part,
      quantity: params[:quantity],
      unit_of_measure: params[:unit_of_measure]
    )
    
    # Create vendor quotations for selected suppliers
    params[:supplier_ids].each do |supplier_id|
      @rfq.vendor_quotations.create!(
        supplier_id: supplier_id,
        status: 'draft'
      )
    end
    
    # Send emails
    @rfq.vendor_quotations.each do |quote|
      VendorRfqMailer.send_to_supplier(quote).deliver_later if defined?(VendorRfqMailer)
    end
    
    redirect_to vmcott_parts_coordinator_dashboard_path, 
                notice: "RFQ ##{@rfq.rfq_number} sent to #{@rfq.vendor_quotations.count} suppliers."
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
    
    @lowest_price = @quotations.map(&:total_amount).min || 0
    @most_frequent_vendor = @rfq.vendor_quotations
                                .group(:supplier_id)
                                .count
                                .max_by { |_, v| v }&.first
    
    render :compare_quotations
  end
  
  def accept_quotation
    @quote = VendorQuotation.find(params[:id])
    @rfq = @quote.vendor_rfq
    
    begin
      po = @rfq.award_to!(quotation: @quote, user: current_user)
      redirect_to purchase_order_path(po), notice: "Quotation accepted. Purchase Order ##{po.po_number} created."
    rescue => e
      redirect_to vmcott_parts_coordinator_compare_rfq_path(@rfq), alert: "Error: #{e.message}"
    end
  end
  
  def receive_parts
    @po = PurchaseOrder.find(params[:purchase_order_id])
    
    if defined?(VendorInvoice)
      invoice = VendorInvoice.create!(
        purchase_order: @po,
        supplier_id: @po.supplier_id,
        invoice_number: params[:invoice_number],
        amount: @po.amount,
        status: 'received',
        received_date: Date.current
      )
    end
    
    @po.purchase_order_items.each do |item|
      if item.part.present?
        item.part.update!(
          current_stock: item.part.current_stock + item.quantity
        )
      end
    end
    
    if defined?(VehicleStatus)
      VehicleStatus.where(status: 'parts_ordered').each do |vs|
        vs.update!(status: 'parts_received', current: true)
      end
    end
    
    redirect_to vmcott_parts_coordinator_dashboard_path, notice: "Parts received and stock updated"
  end
  
  private
  
  def require_parts_coordinator
    unless current_user.parts_coordinator? || current_user.admin?
      redirect_to root_path, alert: "Access denied"
    end
  end
  
  def generate_rfq_number
    "RFQ-#{Date.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
  end
end