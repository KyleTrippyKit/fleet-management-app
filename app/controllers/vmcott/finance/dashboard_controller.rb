# app/controllers/vmcott/finance/dashboard_controller.rb
# Finance & Accounting Controller - Handles quotations, PO approval, invoicing
# Kept as 'finance' for backward compatibility with alias 'finance_accounting'

class Vmcott::Finance::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_finance
  before_action :ensure_can_review_quotes, only: [:compare_quotations, :select_quotation]
  before_action :ensure_can_approve_po, only: [:approve_po, :reject_po]

  def index
    # TRACK 1: In-stock parts ready for agency quotation
    @ready_for_quotation = Inspection.where(status: 'awaiting_customer_approval')
                                     .joins(:parts_requests)
                                     .where(parts_requests: { in_stock: true })
                                     .distinct
                                     .includes(:vehicle, :inspection_jobs, :parts_requests)
                                     .order(updated_at: :asc)

    # TRACK 2: Vendor quotations ready for comparison (from procurement)
    @quotations_to_review = VendorRfq.where(finance_review_ready: true)
                                     .joins(:vendor_quotations)
                                     .where(vendor_quotations: { status: 'received' })
                                     .distinct
                                     .includes(:vendor_rfq_items, :vendor_quotations)
                                     .order(updated_at: :desc)

    # TRACK 3: Purchase orders pending approval (from agency)
    @pending_pos = PurchaseOrder.where(status: 'pending_approval')
                                .includes(:supplier, :vehicle)
                                .order(created_at: :asc)

    # TRACK 4: Vehicles ready for pickup - need invoicing (with PO reference)
    @ready_for_pickup = Inspection.where(status: 'ready_for_pickup')
                                  .includes(:vehicle, :purchase_order)
                                  .order(ready_for_pickup_at: :asc)

    # Additional work that needs quotation (optional)
    @additional_work_needs_quote = Inspection.where(status: 'qc_completed')
                                             .where("notes LIKE ?", "%additional issues%")
                                             .includes(:vehicle)
                                             .order(updated_at: :desc)

    # KPI counts
    @ready_for_quotation_count = @ready_for_quotation.count
    @quotations_to_review_count = @quotations_to_review.count
    @pending_po_approval_count = @pending_pos.count
    @ready_for_pickup_count = @ready_for_pickup.count
    @additional_work_count = @additional_work_needs_quote.count
    
    # Financial KPI
    @total_pending_invoices = Invoice.where(status: ['pending', 'pending_payment']).count
    @total_overdue_invoices = Invoice.overdue.count
    @total_pending_amount = Invoice.where(status: ['pending', 'pending_payment']).sum(:amount)
    @total_overdue_amount = Invoice.overdue.sum(:amount)
    
    # Stats for KPI cards
    @stats = {
      ready_for_quotation: @ready_for_quotation_count,
      quotations_to_review: @quotations_to_review_count,
      pending_po_approval: @pending_po_approval_count,
      ready_for_pickup: @ready_for_pickup_count,
      additional_work: @additional_work_count,
      pending_invoices: @total_pending_invoices,
      overdue_invoices: @total_overdue_invoices,
      pending_amount: @total_pending_amount,
      overdue_amount: @total_overdue_amount
    }
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
    
    # Update RFQ with awarded quotation
    rfq.update(
      awarded_vendor_quotation_id: quotation.id,
      awarded_at: Time.current,
      status: 'awarded'
    )
    
    # Create purchase order from quotation (for parts procurement)
    po = PurchaseOrder.new(
      supplier_id: quotation.supplier_id,
      vendor: quotation.supplier.name,
      amount: quotation.vendor_quotation_lines.sum(:total_price),
      status: 'pending_approval',
      notes: "Created from RFQ ##{rfq.rfq_number} for parts procurement",
      payment_terms: params[:payment_terms] || 'net_30',
      created_by_id: current_user.id
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
      
      # Notify inventory manager
      if defined?(Notification)
        User.where(role: ['inventory_manager', 'admin']).each do |user|
          Notification.create(
            user: user,
            title: "Purchase Order Created",
            message: "PO ##{po.po_number} has been created and needs ordering.",
            notifiable: po,
            link: purchase_order_path(po)
          )
        end
      end
      
      redirect_to purchase_order_path(po), notice: "Quotation selected and purchase order created for parts procurement."
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
      
      # Notify inventory manager
      if defined?(Notification)
        User.where(role: ['inventory_manager', 'admin']).each do |user|
          Notification.create(
            user: user,
            title: "Purchase Order Approved",
            message: "PO ##{po.po_number} has been approved and is ready to order.",
            notifiable: po,
            link: purchase_order_path(po)
          )
        end
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
      
      # Notify procurement team
      if defined?(Notification)
        User.where(role: ['procurement', 'admin']).each do |user|
          Notification.create(
            user: user,
            title: "Purchase Order Rejected",
            message: "PO ##{po.po_number} was rejected. Reason: #{params[:rejection_reason]}",
            notifiable: po,
            link: vmcott_procurement_dashboard_path
          )
        end
      end
      
      redirect_to vmcott_finance_dashboard_path, notice: "Purchase order rejected."
    else
      redirect_to vmcott_finance_dashboard_path, alert: "Error rejecting purchase order."
    end
  end

  # This creates the quotation that goes to the agency (PTSC)
  def create_agency_quotation
    inspection = Inspection.find(params[:inspection_id])
    
    # Calculate costs
    labor_cost = inspection.inspection_jobs.sum(:estimated_labor_cost)
    parts_cost = inspection.parts_requests.where(in_stock: true).sum { |pr| (pr.part&.sale_price || 0) * pr.quantity }
    total_amount = labor_cost + parts_cost
    
    # Create quotation for agency
    quotation = Quotation.new(
      vehicle_id: inspection.vehicle_id,
      agency_id: inspection.vehicle.agency_id,
      quote_number: "Q-#{Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}",
      valid_from: Date.today,
      valid_to: Date.today + 30.days,
      amount: total_amount,
      subtotal: total_amount,
      status: 'draft',
      vendor: 'VMCOTT',
      notes: "Quotation for inspection ##{inspection.id}",
      created_by_id: current_user.id
    )
    
    if quotation.save
      # Add labor line items
      inspection.inspection_jobs.each do |job|
        QuotationLineItem.create(
          quotation_id: quotation.id,
          description: "Labor: #{job.description}",
          quantity: 1,
          unit_price: job.estimated_labor_cost
        )
      end
      
      # Add parts line items
      inspection.parts_requests.where(in_stock: true).each do |pr|
        QuotationLineItem.create(
          quotation_id: quotation.id,
          description: "Part: #{pr.part&.name || pr.custom_part_name}",
          quantity: pr.quantity,
          unit_price: pr.part&.sale_price || 0,
          part_id: pr.part_id
        )
      end
      
      # Update inspection status
      inspection.update(status: 'quotation_sent')
      
      redirect_to quotation_path(quotation), notice: "Agency quotation created successfully."
    else
      redirect_to vmcott_finance_dashboard_path, alert: "Error creating quotation: #{quotation.errors.full_messages.join(', ')}"
    end
  end

  # This creates the final invoice that references the agency's PO
  def create_invoice
    inspection = Inspection.find(params[:inspection_id])
    
    # Only allow invoicing for ready_for_pickup
    unless inspection.ready_for_pickup?
      redirect_to vmcott_finance_dashboard_path, alert: "Vehicle is not ready for pickup yet."
      return
    end
    
    # Find the agency's PO (Purchase Order from PTSC that authorized the work)
    agency_po = inspection.purchase_order
    
    unless agency_po
      redirect_to vmcott_finance_dashboard_path, alert: "No agency purchase order found for this inspection. Cannot create invoice without PO reference."
      return
    end
    
    # Calculate totals
    total_labor = inspection.inspection_jobs.sum(:estimated_labor_cost)
    total_parts = inspection.parts_requests.sum { |pr| (pr.part&.sale_price || 0) * pr.quantity }
    total_amount = total_labor + total_parts
    
    # Create invoice that references the agency's PO
    invoice = Invoice.new(
      vehicle_id: inspection.vehicle_id,
      purchase_order_id: agency_po.id,  # CRITICAL: Reference the agency's PO
      invoice_number: "INV-#{Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}",
      invoice_date: Date.today,
      due_date: Date.today + 30.days,
      amount: total_amount,
      subtotal: total_amount,
      status: 'pending',
      vendor: 'VMCOTT',
      payment_terms: agency_po.payment_terms || 'net_30',
      notes: "PO Reference: #{agency_po.po_number} - Inspection ##{inspection.id}"
    )
    
    if invoice.save
      # Add labor line items
      inspection.inspection_jobs.each do |job|
        InvoiceLineItem.create(
          invoice_id: invoice.id,
          description: "Labor: #{job.description}",
          quantity: 1,
          unit_price: job.estimated_labor_cost,
          total_price: job.estimated_labor_cost
        )
      end
      
      # Add parts line items
      inspection.parts_requests.each do |pr|
        unit_price = pr.part&.sale_price || 0
        line_total = unit_price * pr.quantity
        
        InvoiceLineItem.create(
          invoice_id: invoice.id,
          description: "Part: #{pr.part&.name || pr.custom_part_name}",
          quantity: pr.quantity,
          unit_price: unit_price,
          total_price: line_total,
          part_id: pr.part_id
        )
      end
      
      # Update inspection status
      inspection.update(status: 'invoiced')
      
      # Send notifications
      if defined?(Notification)
        # Notify admin
        User.where(role: 'admin').each do |admin|
          Notification.create(
            user: admin,
            title: "Invoice Created",
            message: "Invoice ##{invoice.invoice_number} created for vehicle #{inspection.vehicle.license_plate} referencing PO ##{agency_po.po_number}.",
            notifiable: invoice,
            link: invoice_path(invoice)
          )
        end
        
        # Notify agency (PTSC) finance team
        agency = inspection.vehicle.agency
        if agency && agency.code == 'PTSC'
          User.where(agency_id: agency.id, role: ['finance', 'fleet_manager']).each do |agency_user|
            Notification.create(
              user: agency_user,
              title: "New Invoice from VMCOTT",
              message: "Invoice ##{invoice.invoice_number} for #{inspection.vehicle.license_plate} is ready for review.",
              notifiable: invoice,
              link: invoice_path(invoice)
            )
          end
        end
      end
      
      redirect_to invoice_path(invoice), notice: "Invoice created successfully referencing PO ##{agency_po.po_number}."
    else
      redirect_to vmcott_finance_dashboard_path, alert: "Error creating invoice: #{invoice.errors.full_messages.join(', ')}"
    end
  end

  # Financial Reports
  def reports
    @start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : 30.days.ago.to_date
    @end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : Date.today
    
    @invoices = Invoice.where(created_at: @start_date.beginning_of_day..@end_date.end_of_day)
    @total_invoiced = @invoices.sum(:amount)
    @total_paid = @invoices.where(status: 'paid').sum(:amount)
    @total_pending = @invoices.where(status: ['pending', 'pending_payment']).sum(:amount)
    
    @invoices_by_agency = @invoices.joins(vehicle: :agency)
                                   .group('agencies.code')
                                   .sum(:amount)
    
    @monthly_totals = @invoices.group_by_month(:created_at).sum(:amount)
  end

  def aging_report
    @invoices = Invoice.includes(vehicle: :agency)
                       .where(status: ['pending', 'pending_payment', 'overdue'])
                       .order(due_date: :asc)
    
    @current = @invoices.where('due_date > ?', Date.today)
    @overdue_1_30 = @invoices.where(due_date: (Date.today - 30.days)..Date.today)
    @overdue_31_60 = @invoices.where(due_date: (Date.today - 60.days)..(Date.today - 31.days))
    @overdue_61_90 = @invoices.where(due_date: (Date.today - 90.days)..(Date.today - 61.days))
    @overdue_90_plus = @invoices.where('due_date < ?', Date.today - 90.days)
    
    @aging_summary = {
      current: @current.sum(:amount),
      overdue_1_30: @overdue_1_30.sum(:amount),
      overdue_31_60: @overdue_31_60.sum(:amount),
      overdue_61_90: @overdue_61_90.sum(:amount),
      overdue_90_plus: @overdue_90_plus.sum(:amount),
      total: @invoices.sum(:amount)
    }
  end

  private

  def require_finance
    unless current_user.finance? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Finance & Accounting privileges required."
    end
  end

  def ensure_can_review_quotes
    rfq = VendorRfq.find_by(id: params[:rfq_id])
    return unless rfq
    
    unless rfq.vendor_quotations.where(status: 'received').any?
      redirect_to vmcott_finance_dashboard_path, 
                  alert: "This RFQ has no quotations received yet."
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