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
    
    # Automatically looks for: app/views/vmcott/parts_coordinator/dashboard/index.html.erb
  end
  
  def create_rfq
    @part = Part.find(params[:part_id])
    @rfq = VendorRfq.new(
      part: @part,
      quantity: params[:quantity] || @part.reorder_quantity,
      created_by: current_user,
      status: 'draft'
    )
    
    @part.vendor_parts.where(is_preferred: true).each do |vp|
      @rfq.vendor_quotations.build(supplier: vp.supplier)
    end
    
    # Automatically looks for: app/views/vmcott/parts_coordinator/dashboard/create_rfq.html.erb
  end
  
  def send_rfq
    @rfq = VendorRfq.find(params[:id])
    @rfq.update(status: 'sent', sent_at: Time.current)
    
    @rfq.vendor_quotations.each do |quote|
      VendorRfqMailer.send_to_supplier(quote).deliver_later if defined?(VendorRfqMailer)
    end
    
    redirect_to vmcott_parts_coordinator_dashboard_path, notice: "RFQ sent to suppliers"
  end
  
  def compare_quotations
    @rfq = VendorRfq.find(params[:id])
    @quotations = @rfq.vendor_quotations.received
    
    @lowest_price = @quotations.minimum(:total_amount)
    @most_frequent_vendor = @rfq.vendor_quotations
                                .group(:supplier_id)
                                .count
                                .max_by { |_, v| v }&.first
    
    # Automatically looks for: app/views/vmcott/parts_coordinator/dashboard/compare_quotations.html.erb
  end
  
  def accept_quotation
    @quote = VendorQuotation.find(params[:id])
    @quote.update!(status: 'accepted')
    
    po = PurchaseOrder.create!(
      vendor: @quote.supplier.name,
      amount: @quote.total_amount,
      status: 'approved',
      created_by: current_user,
      notes: "From RFQ ##{@quote.vendor_rfq.id}",
      payment_status: 'unpaid'
    )
    
    @quote.vendor_quotation_lines.each do |line|
      po.purchase_order_items.create!(
        part_id: line.part_id,
        description: line.description,
        quantity: line.quantity,
        unit_price: line.unit_price,
        total_price: line.total_price
      )
    end
    
    po.recalculate_amount!
    
    redirect_to vmcott_parts_coordinator_dashboard_path, 
                notice: "Quotation accepted. Purchase Order ##{po.po_number} created."
  end
  
  def receive_parts
    @po = PurchaseOrder.find(params[:purchase_order_id])
    
    invoice = VendorInvoice.create!(
      purchase_order: @po,
      supplier_id: @po.supplier_id,
      invoice_number: params[:invoice_number],
      amount: @po.amount,
      status: 'received',
      received_date: Date.current
    ) if defined?(VendorInvoice)
    
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
end