# app/controllers/vmcott/finance/dashboard_controller.rb
class Vmcott::Finance::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_finance

  def index
    # RFQs with quotations received (from billing team)
    # Using a simpler approach - get all RFQs that have received quotations
    @quotations_for_review = VendorRfq.joins(:vendor_quotations)
                                      .where(vendor_quotations: { status: 'received' })
                                      .distinct
                                      .includes(:vendor_rfq_items, :vendor_quotations)
                                      .order(updated_at: :desc)

    # Purchase orders pending approval
    @pending_pos = PurchaseOrder.where(status: 'pending_approval')
                                .includes(:supplier)
                                .order(created_at: :asc)

    # Vehicles ready for pickup (need invoicing)
    @ready_for_pickup = Inspection.where(status: 'ready_for_pickup')
                                  .includes(:vehicle)
                                  .order(ready_for_pickup_at: :asc)

    # KPI counts
    @quotations_to_review_count = @quotations_for_review.count
    @pending_po_approval_count = @pending_pos.count
    @ready_for_pickup_count = @ready_for_pickup.count
  end

  def compare_quotations
    @rfq = VendorRfq.find(params[:rfq_id])
    @quotations = @rfq.vendor_quotations.includes(:supplier, :vendor_quotation_lines)
    
    # Group quotations by part for comparison
    @parts_comparison = {}
    
    @rfq.vendor_rfq_items.each do |item|
      part_name = item.part&.name || item.custom_part_name || item.description
      @parts_comparison[part_name] = {
        quantity: item.quantity,
        quotations: []
      }
      
      @quotations.each do |quote|
        # Find matching quotation line
        quote_line = quote.vendor_quotation_lines.find_by(part_id: item.part_id)
        if quote_line
          @parts_comparison[part_name][:quotations] << {
            supplier_id: quote.supplier_id,
            supplier_name: quote.supplier.name,
            unit_price: quote_line.unit_price,
            total_price: quote_line.total_price,
            quotation_id: quote.id
          }
        end
      end
      
      # Sort by price (lowest first)
      @parts_comparison[part_name][:quotations].sort_by! { |q| q[:unit_price] }
    end
    
    # Calculate lowest total for each supplier
    @supplier_totals = {}
    @quotations.each do |quote|
      total = quote.vendor_quotation_lines.sum(:total_price)
      @supplier_totals[quote.supplier_id] = {
        supplier_name: quote.supplier.name,
        total: total,
        quotation_id: quote.id
      }
    end
    
    # Find the lowest overall total
    @lowest_total = @supplier_totals.values.min_by { |s| s[:total] }
  end

  def select_quotation
    quotation = VendorQuotation.find(params[:quotation_id])
    rfq = quotation.vendor_rfq
    
    # Mark selected quotation
    quotation.update(selected: true)
    
    # Update RFQ with awarded quotation
    rfq.update(
      awarded_vendor_quotation_id: quotation.id,
      awarded_at: Time.current,
      status: 'awarded'
    )
    
    # Create purchase order from quotation
    po = PurchaseOrder.new(
      supplier_id: quotation.supplier_id,
      vendor: quotation.supplier.name,
      amount: quotation.vendor_quotation_lines.sum(:total_price),
      status: 'pending_approval',
      notes: "Created from RFQ ##{rfq.rfq_number}",
      payment_terms: params[:payment_terms] || 'net_30'
    )
    
    if po.save
      # Create purchase order items from quotation lines
      quotation.vendor_quotation_lines.each do |line|
        po.purchase_order_items.create(
          part_id: line.part_id,
          description: line.description || line.part&.name,
          quantity: line.quantity,
          unit_price: line.unit_price,
          total_price: line.total_price
        )
      end
      
      # Update parts requests to link to this purchase order
      rfq.vendor_rfq_items.each do |item|
        PartsRequest.where(part_id: item.part_id)
                   .where(status: 'quotations_received')
                   .update_all(
                     status: 'ordered',
                     purchase_order_id: po.id
                   )
      end
      
      # Notify parts coordinator that PO is created
      User.where(role: 'parts_coordinator').each do |pc|
        Notification.create(
          user: pc,
          title: "Purchase Order Created",
          message: "PO ##{po.po_number} has been created and needs ordering.",
          notifiable: po,
          link: purchase_order_path(po)
        )
      end
      
      redirect_to purchase_order_path(po), notice: "Quotation selected and purchase order created."
    else
      redirect_to vmcott_finance_compare_quotations_path(rfq_id: rfq.id), 
                  alert: "Error creating purchase order: #{po.errors.full_messages.join(', ')}"
    end
  end

  def approve_po
    po = PurchaseOrder.find(params[:id])
    
    if po.update(
        status: 'approved', 
        approved_at: Time.current, 
        approved_by_id: current_user.id
      )
      
      # Notify parts coordinator that PO is approved and ready to order
      User.where(role: 'parts_coordinator').each do |pc|
        Notification.create(
          user: pc,
          title: "Purchase Order Approved",
          message: "PO ##{po.po_number} has been approved and is ready to order.",
          notifiable: po,
          link: purchase_order_path(po)
        )
      end
      
      redirect_to purchase_order_path(po), notice: "Purchase order approved."
    else
      redirect_to vmcott_finance_dashboard_path, alert: "Error approving purchase order."
    end
  end

  def reject_po
    po = PurchaseOrder.find(params[:id])
    
    if po.update(
        status: 'rejected',
        rejection_reason: params[:rejection_reason],
        rejected_at: Time.current,
        rejected_by_id: current_user.id
      )
      
      # Notify billing team that PO was rejected
      User.where(role: 'billing').each do |billing_user|
        Notification.create(
          user: billing_user,
          title: "Purchase Order Rejected",
          message: "PO ##{po.po_number} was rejected. Reason: #{params[:rejection_reason]}",
          notifiable: po,
          link: vmcott_billing_dashboard_path
        )
      end
      
      redirect_to vmcott_finance_dashboard_path, notice: "Purchase order rejected."
    else
      redirect_to vmcott_finance_dashboard_path, alert: "Error rejecting purchase order."
    end
  end

  def create_invoice
    inspection = Inspection.find(params[:inspection_id])
    
    # Calculate totals
    total_labor = inspection.inspection_jobs.sum(:estimated_labor_cost)
    
    # Calculate parts total from parts requests
    total_parts = 0
    parts_details = []
    
    inspection.parts_requests.each do |pr|
      if pr.part.present?
        # Use sale price from part
        price = pr.part.sale_price || pr.part.price || 0
        line_total = price * pr.quantity
        total_parts += line_total
        
        parts_details << {
          description: pr.part.name,
          quantity: pr.quantity,
          unit_price: price,
          total: line_total,
          part_id: pr.part_id
        }
      elsif pr.purchase_order.present?
        # Use actual cost from purchase order if available
        po_item = pr.purchase_order.purchase_order_items.find_by(part_id: pr.part_id)
        if po_item
          line_total = po_item.unit_price * pr.quantity
          total_parts += line_total
          
          parts_details << {
            description: pr.custom_part_name || po_item.description,
            quantity: pr.quantity,
            unit_price: po_item.unit_price,
            total: line_total,
            part_id: pr.part_id
          }
        end
      else
        # Custom part with no price yet
        parts_details << {
          description: pr.custom_part_name || "Unknown Part",
          quantity: pr.quantity,
          unit_price: 0,
          total: 0
        }
      end
    end
    
    total_amount = total_labor + total_parts
    
    invoice = Invoice.new(
      vehicle_id: inspection.vehicle_id,
      inspection_id: inspection.id,
      invoice_number: "INV-#{Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}",
      invoice_date: Date.today,
      due_date: Date.today + 30.days,
      amount: total_amount,
      subtotal: total_amount,
      status: 'pending',
      vendor: 'VMCOTT',
      payment_terms: params[:payment_terms] || 'net_30'
    )
    
    if invoice.save
      # Add labor line items
      inspection.inspection_jobs.each do |job|
        invoice.invoice_line_items.create(
          description: "Labor: #{job.description}",
          quantity: 1,
          unit_price: job.estimated_labor_cost,
          total_price: job.estimated_labor_cost
        )
      end
      
      # Add parts line items
      parts_details.each do |part|
        invoice.invoice_line_items.create(
          description: "Part: #{part[:description]}",
          quantity: part[:quantity],
          unit_price: part[:unit_price],
          total_price: part[:total],
          part_id: part[:part_id]
        )
      end
      
      # Update inspection status
      inspection.update(status: 'invoiced')
      
      # Notify admin/agency that invoice is ready
      User.where(role: 'admin').each do |admin|
        Notification.create(
          user: admin,
          title: "Invoice Created",
          message: "Invoice ##{invoice.invoice_number} created for vehicle #{inspection.vehicle.license_plate}.",
          notifiable: invoice,
          link: invoice_path(invoice)
        )
      end
      
      redirect_to invoice_path(invoice), notice: "Invoice created successfully."
    else
      redirect_to vmcott_finance_dashboard_path, alert: "Error creating invoice: #{invoice.errors.full_messages.join(', ')}"
    end
  end

  private

  def require_finance
    unless current_user.finance? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Finance privileges required."
    end
  end
end