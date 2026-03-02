# app/controllers/vmcott/finance/dashboard_controller.rb
class Vmcott::Finance::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_finance
  before_action :ensure_can_review_quotes, only: [:compare_quotations, :select_quotation]
  before_action :ensure_can_approve_po, only: [:approve_po, :reject_po]

  def index
    # FIXED: Only show what finance needs to see
    @quotations_for_review = VendorRfq.joins(:vendor_quotations)
                                      .where(vendor_quotations: { status: 'received' })
                                      .distinct
                                      .includes(:vendor_rfq_items, :vendor_quotations)
                                      .order(updated_at: :desc)

    @inspections_ready_for_quote = Inspection.where(status: 'parts_coordinator_review')
                                             .joins(:parts_requests)
                                             .where(parts_requests: { in_stock: true })
                                             .distinct
                                             .includes(:vehicle, :inspection_jobs, :parts_requests)

    @pending_pos = PurchaseOrder.where(status: 'pending_approval')
                                .includes(:supplier)
                                .order(created_at: :asc)

    @ready_for_pickup = Inspection.where(status: 'ready_for_pickup')
                                  .includes(:vehicle)
                                  .order(ready_for_pickup_at: :asc)

    @additional_work_needs_quote = Inspection.where(status: 'qc_completed')
                                             .where("notes LIKE ?", "%additional issues%")
                                             .includes(:vehicle)
                                             .order(updated_at: :desc)

    # KPI counts
    @quotations_to_review_count = @quotations_for_review.count
    @inspections_ready_for_quote_count = @inspections_ready_for_quote.count
    @pending_po_approval_count = @pending_pos.count
    @ready_for_pickup_count = @ready_for_pickup.count
    @additional_work_count = @additional_work_needs_quote.count
  end

  def compare_quotations
    @rfq = VendorRfq.find(params[:rfq_id])
    @quotations = @rfq.vendor_quotations.includes(:supplier, :vendor_quotation_lines)
    
    @parts_comparison = {}
    
    @rfq.vendor_rfq_items.each do |item|
      part_name = item.part&.name || item.custom_part_name || item.description
      @parts_comparison[part_name] = {
        quantity: item.quantity,
        quotations: []
      }
      
      @quotations.each do |quote|
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
      
      @parts_comparison[part_name][:quotations].sort_by! { |q| q[:unit_price] }
    end
    
    @supplier_totals = {}
    @quotations.each do |quote|
      total = quote.vendor_quotation_lines.sum(:total_price)
      @supplier_totals[quote.supplier_id] = {
        supplier_name: quote.supplier.name,
        total: total,
        quotation_id: quote.id
      }
    end
    
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
      quotation.vendor_quotation_lines.each do |line|
        po.purchase_order_items.create(
          part_id: line.part_id,
          description: line.description || line.part&.name,
          quantity: line.quantity,
          unit_price: line.unit_price,
          total_price: line.total_price
        )
      end
      
      rfq.vendor_rfq_items.each do |item|
        PartsRequest.where(part_id: item.part_id)
                   .where(status: 'quotations_received')
                   .update_all(
                     status: 'ordered',
                     purchase_order_id: po.id
                   )
      end
      
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
    
    # FIXED: Only allow invoicing for ready_for_pickup
    unless inspection.ready_for_pickup?
      redirect_to vmcott_finance_dashboard_path, alert: "Vehicle is not ready for pickup yet."
      return
    end
    
    total_labor = inspection.inspection_jobs.sum(:estimated_labor_cost)
    
    total_parts = 0
    parts_details = []
    
    inspection.parts_requests.each do |pr|
      if pr.part.present?
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
      inspection.inspection_jobs.each do |job|
        invoice.invoice_line_items.create(
          description: "Labor: #{job.description}",
          quantity: 1,
          unit_price: job.estimated_labor_cost,
          total_price: job.estimated_labor_cost
        )
      end
      
      parts_details.each do |part|
        invoice.invoice_line_items.create(
          description: "Part: #{part[:description]}",
          quantity: part[:quantity],
          unit_price: part[:unit_price],
          total_price: part[:total],
          part_id: part[:part_id]
        )
      end
      
      inspection.update(status: 'invoiced')
      
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

  def ensure_can_review_quotes
    rfq = VendorRfq.find_by(id: params[:rfq_id])
    return unless rfq
    
    unless rfq.status == 'quotations_received'
      redirect_to vmcott_finance_dashboard_path, 
                  alert: "This RFQ is not ready for quotation review."
      return false
    end
  end

  def ensure_can_approve_po
    po = PurchaseOrder.find_by(id: params[:id])
    return unless po
    
    unless po.status == 'pending_approval'
      redirect_to vmcott_finance_dashboard_path, 
                  alert: "This purchase order is not pending approval."
      return false
    end
  end
end