# app/controllers/purchase_orders_controller.rb
class PurchaseOrdersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_purchase_order, except: [:index, :new, :create, :from_quotation, :awaiting_acceptance]
  before_action :check_edit_permission, only: [:edit, :update]
  before_action :require_finance, only: [:mark_paid, :payment, :process_payment, :authorize_payment, :complete_payment, :record_payment]
  before_action :redirect_pdf_to_print, only: [:show]

  # GET /purchase_orders
  def index
    @purchase_orders = fetch_purchase_orders
    @agencies = Agency.all if current_user.admin? || current_user.finance?
    @users = User.all if current_user.admin? || current_user.supervisor? || current_user.finance?

    @purchase_orders.each do |po|
      if po.status.nil? || po.payment_status.nil?
        po.update_columns(status: 'draft', payment_status: 'unpaid') if po.persisted?
      end
    end
  end

  # GET /purchase_orders/from_quotation/:quotation_id
  def from_quotation
    @quotation = Quotation.find(params[:quotation_id])

    unless current_user.finance? || current_user.admin? || current_user.supervisor?
      redirect_to @quotation, alert: 'Access denied. Finance, admin, or supervisor role required.'
      return
    end

    if @quotation.purchase_order.present?
      redirect_to purchase_order_path(@quotation.purchase_order),
                  notice: 'Purchase order already exists for this quotation.'
      return
    end

    accepted_total = calculate_accepted_total(@quotation)

    @purchase_order = PurchaseOrder.new(
      vehicle_id: @quotation.vehicle_id,
      vendor: @quotation.vendor,
      amount: accepted_total,
      notes: "Created from Quotation #{@quotation.quote_number}\nAccepted items only.",
      created_by_id: current_user.id,
      status: 'draft',
      po_number: generate_po_number,
      quotation_id: @quotation.id
    )

    @quotation.quotation_line_items.each do |line_item|
      @purchase_order.purchase_order_items.build(
        description: line_item.description,
        quantity: line_item.quantity,
        unit_price: line_item.unit_price,
        notes: line_item.specifications,
        is_accepted: nil
      )
    end

    if @quotation.respond_to?(:quotation_jobs)
      @quotation.quotation_jobs.each do |job|
        @purchase_order.purchase_order_items.build(
          description: "Labor: #{job.name}",
          quantity: 1,
          unit_price: job.total_labor_cost || 0,
          notes: job.description,
          is_accepted: nil
        )

        job.quotation_job_parts.each do |job_part|
          @purchase_order.purchase_order_items.build(
            part_id: job_part.part_id,
            description: job_part.part&.name || "Part from #{job.name}",
            quantity: job_part.quantity,
            unit_price: job_part.unit_price,
            notes: "From job: #{job.name}",
            is_accepted: nil
          )
        end
      end
    end

    if @purchase_order.save
      @quotation.update(status: 'accepted', accepted_at: Time.current)
      redirect_to @purchase_order, notice: 'Purchase order created from accepted quotation items.'
    else
      Rails.logger.error "Failed to create purchase order: #{@purchase_order.errors.full_messages.join(', ')}"
      redirect_to accept_items_quotation_path(@quotation),
                  alert: "Failed to create purchase order: #{@purchase_order.errors.full_messages.join(', ')}"
    end
  end

  # GET /purchase_orders/awaiting_acceptance
  def awaiting_acceptance
    return redirect_to purchase_orders_path, alert: 'VMCOTT access only' unless current_user.agency&.code == 'VMCOTT'

    @purchase_orders = PurchaseOrder.where(vendor: 'VMCOTT')
                                    .where(acceptance_acknowledged_at: nil)
                                    .order(created_at: :desc)
                                    .includes(:vehicle, :created_by)
                                    .page(params[:page])

    render :awaiting_acceptance
  end

  # POST /purchase_orders/:id/acknowledge_acceptance
  def acknowledge_acceptance
    return redirect_to @purchase_order, alert: 'VMCOTT access only' unless current_user.agency&.code == 'VMCOTT'

    if @purchase_order.update(acceptance_acknowledged_at: Time.current)
      redirect_to @purchase_order, notice: 'Purchase order acceptance acknowledged.'
    else
      redirect_to @purchase_order, alert: 'Failed to acknowledge acceptance.'
    end
  end

  # POST /purchase_orders/:id/create_vmcott_pos
  def create_vmcott_pos
    return redirect_to @purchase_order, alert: 'VMCOTT access only' unless current_user.agency&.code == 'VMCOTT'

    if @purchase_order.internal_pos.present?
      redirect_to vmcott_internal_pos_path(@purchase_order.internal_pos),
                  notice: 'Internal POS already exists for this PO.'
      return
    end

    @internal_pos = InternalPos.create!(
      purchase_order: @purchase_order,
      vehicle: @purchase_order.vehicle,
      work_order_number: InternalPos.generate_work_order_number,
      assigned_to: current_user,
      priority: 'normal',
      status: 'pending',
      created_by: current_user,
      notes: "Created from PO #{@purchase_order.po_number}"
    )

    redirect_to from_po_vmcott_internal_pos_path(purchase_order_id: @purchase_order.id),
                notice: 'Internal POS created. Please assign technician and complete details.'
  end

  # GET /purchase_orders/:id/acceptance_details
  def acceptance_details
    @accepted_items = @purchase_order.purchase_order_items.where(is_accepted: true)
    @rejected_items = @purchase_order.purchase_order_items.where(is_accepted: false)
    @pending_items = @purchase_order.purchase_order_items.where(is_accepted: nil)
    @accepted_total = @accepted_items.sum(:total_price)

    @show_simple_workflow = true
    render :acceptance_details
  end

  # POST /purchase_orders/:id/accept_entire_po - VMCOTT accepting work order
  def accept_entire_po
    if @purchase_order.accept_entire_po!(current_user)
      PurchaseOrderMailer.po_approved(@purchase_order).deliver_later if defined?(PurchaseOrderMailer)
      redirect_to @purchase_order, notice: 'Purchase order accepted successfully. Work has been started.'
    else
      redirect_to @purchase_order, alert: 'Could not accept purchase order.'
    end
  end

  # PATCH /purchase_orders/:id/update_item_acceptance
  def update_item_acceptance
    return redirect_to @purchase_order, alert: 'VMCOTT access only' unless current_user.agency&.code == 'VMCOTT'

    item = @purchase_order.purchase_order_items.find(params[:item_id])

    accepted_value = case params[:accepted]
                     when 'true' then true
                     when 'false' then false
                     when 'pending', 'nil', 'null' then nil
                     else params[:accepted]
                     end

    if item.update(is_accepted: accepted_value, rejection_reason: params[:reason])
      @purchase_order.recompute_acceptance_status!

      if request.xhr?
        render json: {
          success: true,
          accepted_total: @purchase_order.accepted_amount,
          pending_items: @purchase_order.purchase_order_items.where(is_accepted: nil).count
        }
      else
        redirect_to acceptance_details_purchase_order_path(@purchase_order),
                    notice: 'Item acceptance updated.'
      end
    else
      if request.xhr?
        render json: { success: false, errors: item.errors.full_messages }, status: :unprocessable_entity
      else
        redirect_to acceptance_details_purchase_order_path(@purchase_order),
                    alert: 'Failed to update item acceptance.'
      end
    end
  end

  # GET /purchase_orders/:id
  def show
    if request.format.pdf?
      return redirect_to print_purchase_order_path(@purchase_order, format: :pdf)
    end

    @purchase_order_items = @purchase_order.purchase_order_items
    @invoices = @purchase_order.invoices
    @payable = @purchase_order.respond_to?(:payable) ? @purchase_order.payable : nil

    @payment_histories = @purchase_order.payment_histories.order(created_at: :desc).limit(100)
    @payment_audits = @purchase_order.payment_audits.order(created_at: :asc)

    @vendor_invoice = VendorInvoice.find_by(purchase_order_id: @purchase_order.id)
    @vendor_invoice_items = @vendor_invoice ? @vendor_invoice.vendor_invoice_items : []

    respond_to do |format|
      format.html
      format.json do
        render json: {
          id: @purchase_order.id,
          po_number: @purchase_order.po_number,
          vendor: @purchase_order.agency&.name || @purchase_order.vendor,
          amount: @purchase_order.amount,
          vehicle: {
            make: @purchase_order.vehicle&.make,
            model: @purchase_order.vehicle&.model,
            license_plate: @purchase_order.vehicle&.license_plate,
            year: @purchase_order.vehicle&.year_of_manufacture
          }
        }
      end
    end
  rescue ActiveRecord::StatementInvalid => e
    Rails.logger.warn "Payment histories association failed: #{e.message}"
    @payment_histories = []
    @payment_audits = []

    @vendor_invoice = VendorInvoice.find_by(purchase_order_id: @purchase_order.id)
    @vendor_invoice_items = @vendor_invoice ? @vendor_invoice.vendor_invoice_items : []
  end

  # ENHANCED: New action with RFQ support
  def new
    @purchase_order = PurchaseOrder.new
    @purchase_order.purchase_order_items.build

    if params[:vehicle_id].present?
      @vehicle = Vehicle.find_by(id: params[:vehicle_id])
      @purchase_order.vehicle = @vehicle if @vehicle
    end

    # Handle RFQ data if coming from procurement
    if params[:rfq_id].present?
      @rfq = VendorRfq.find_by(id: params[:rfq_id])
      
      if @rfq.present?
        # 🔥 PREVENT DUPLICATE PO
        if @rfq.po_sent_at.present? || @rfq.po_status == 'sent'
          flash[:alert] = "A purchase order has already been sent for RFQ ##{@rfq.rfq_number}. Cannot create another."
          redirect_to vmcott_procurement_dashboard_path and return
        end
        
        # Get quotations for this RFQ
        @quotations = @rfq.vendor_quotations.where(status: 'received')
        
        # Get vehicle directly from RFQ
        @selected_vehicle_id = @rfq.vehicle_id
        
        if @rfq.vehicle.present?
          @purchase_order.vehicle = @rfq.vehicle
        end
        
        # Build RFQ items data
        @rfq_items_data = @rfq.vendor_rfq_items.map do |item|
          {
            part_id: item.part_id,
            description: item.part&.name || item.custom_part_name || 'Unknown Part',
            quantity: item.quantity
          }
        end
        
        # Build purchase order items from RFQ data
        @purchase_order.purchase_order_items.clear
        @rfq_items_data.each do |item_data|
          @purchase_order.purchase_order_items.build(
            part_id: item_data[:part_id],
            description: item_data[:description],
            quantity: item_data[:quantity],
            unit_price: nil
          )
        end
        
        # Store RFQ ID in session for later association
        session[:rfq_id_for_po] = @rfq.id
        
        if @quotations.present?
          # Build quotations data
          @quotations_data = {
            @rfq.id => {
              items: @rfq_items_data,
              quotations: @quotations.map do |q|
                {
                  supplier_id: q.supplier_id,
                  supplier_name: q.supplier_name,
                  items: q.vendor_quotation_lines.map do |line|
                    {
                      description: line.description,
                      quantity: line.quantity,
                      unit_price: line.unit_price,
                      total: line.total_price
                    }
                  end
                }
              end,
              vehicle_id: @selected_vehicle_id
            }
          }
          
          # Find cheapest overall supplier
          totals = {}
          @quotations.each do |q|
            totals[q.supplier_id] = q.vendor_quotation_lines.sum(:total_price)
          end
          
          if totals.any?
            cheapest_supplier_id = totals.min_by { |_, total| total }&.first
            @cheapest_supplier = Supplier.find_by(id: cheapest_supplier_id)
            @cheapest_total = totals[cheapest_supplier_id]
          end
        end
        
        # Auto-fill vendor from cheapest supplier if available
        if @cheapest_supplier.present?
          @purchase_order.vendor = @cheapest_supplier.name
        end
      end
    end
    
    # Also get available RFQs with quotations for selection
    @available_rfqs = VendorRfq.where(status: 'quotations_received')
                                .includes(:vendor_rfq_items)
                                .includes(:vehicle)
                                .includes(vendor_quotations: :vendor_quotation_lines)
                                .order(created_at: :desc)
  end

  def create
    @purchase_order = PurchaseOrder.new(purchase_order_params)
    @purchase_order.created_by = current_user
    @purchase_order.status = 'draft'

    # 🔥 Associate with RFQ if coming from RFQ
    if session[:rfq_id_for_po].present?
      @purchase_order.rfq_id = session[:rfq_id_for_po]
    end

    if @purchase_order.save
      # Update the RFQ with the PO info
      if @purchase_order.rfq_id.present?
        rfq = VendorRfq.find_by(id: @purchase_order.rfq_id)
        if rfq && rfq.po_sent_at.blank?
          rfq.update(po_status: 'draft')
          Rails.logger.info "✅ Linked RFQ ##{rfq.rfq_number} to PO #{@purchase_order.po_number}"
        end
      end
      
      redirect_to @purchase_order, notice: 'Purchase Order saved as draft successfully.'
    else
      flash.now[:alert] = @purchase_order.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @purchase_order.purchase_order_items.build if @purchase_order.purchase_order_items.empty?
  end

  def update
    if @purchase_order.update(purchase_order_params)
      redirect_to @purchase_order, notice: 'Purchase order updated successfully.'
    else
      flash.now[:alert] = @purchase_order.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  # PROCUREMENT: Send PO to vendor
  def submit
    if @purchase_order.update(status: 'sent', sent_at: Time.current)
      PurchaseOrderMailer.po_created(@purchase_order).deliver_later if defined?(PurchaseOrderMailer)
      
      # 🔥 UPDATE THE RFQ: Mark that PO has been sent
      if @purchase_order.rfq_id.present?
        rfq = VendorRfq.find_by(id: @purchase_order.rfq_id)
        if rfq && rfq.po_sent_at.blank?
          rfq.update(po_sent_at: Time.current, po_status: 'sent')
          Rails.logger.info "✅ Updated RFQ ##{rfq.rfq_number} - PO sent"
        end
      end
      
      # Clear session if present
      session.delete(:rfq_id_for_po)
      
      redirect_to @purchase_order, notice: "Purchase Order sent to #{@purchase_order.vendor} successfully."
    else
      redirect_to @purchase_order, alert: 'Could not send purchase order.'
    end
  end

  # PROCUREMENT: Mark items as received
  def mark_received
    if @purchase_order.update(status: 'received', received_at: Time.current)
      # 🔥 UPDATE THE RFQ: Mark that items have been received
      if @purchase_order.rfq_id.present?
        rfq = VendorRfq.find_by(id: @purchase_order.rfq_id)
        if rfq
          rfq.update(
            po_received_at: Time.current,
            po_status: 'received'
          )
          Rails.logger.info "✅ Updated RFQ ##{rfq.rfq_number} - items received"
        end
      end
      
      notify_inventory_manager(@purchase_order)
      
      # Redirect to dashboard with notice so status updates immediately
      redirect_to vmcott_procurement_dashboard_path, 
                  notice: 'Items marked as received! Status updated to "Items Received ✓".'
    else
      redirect_to @purchase_order, alert: 'Could not mark as received.'
    end
  end

  # PROCUREMENT: Mark as ready for payment
  def mark_ready_for_payment
    if @purchase_order.update(status: 'ready_for_payment', ready_for_payment_at: Time.current)
      notify_finance(@purchase_order)
      redirect_to @purchase_order, notice: 'Order marked ready for payment. Finance has been notified.'
    else
      redirect_to @purchase_order, alert: 'Could not mark as ready for payment.'
    end
  end

  # INVENTORY: Update stock levels
  def update_stock
    ActiveRecord::Base.transaction do
      @purchase_order.purchase_order_items.each do |item|
        if item.part_id.present?
          part = Part.find(item.part_id)
          part.update!(current_stock: part.current_stock + item.quantity)
        end
      end
      
      @purchase_order.update(
        status: 'stock_updated',
        stock_updated_at: Time.current
      )
      
      notify_workshop(@purchase_order)
      
      redirect_to @purchase_order, notice: 'Stock updated successfully. Workshop has been notified.'
    end
  rescue => e
    redirect_to @purchase_order, alert: "Failed to update stock: #{e.message}"
  end

  # FINANCE: Process payment
  def mark_paid
    begin
      card_type = params[:card_type]
      last_four_digits = params[:last_four_digits]

      if @purchase_order.mark_as_paid!(
        reference: params[:payment_reference],
        method: params[:payment_method],
        user: current_user,
        notes: params[:payment_notes],
        last_four_digits: last_four_digits,
        card_type: card_type
      )
        payable = @purchase_order.respond_to?(:payable) ? @purchase_order.payable : nil
        payable&.record_payment(@purchase_order.amount, params[:payment_method], params[:payment_reference])
        
        PurchaseOrderMailer.po_paid(@purchase_order).deliver_later if defined?(PurchaseOrderMailer)
        
        redirect_to @purchase_order, notice: 'Payment processed successfully. Vendor notified.'
      else
        redirect_to @purchase_order, alert: 'Could not process payment.'
      end
    rescue ActiveRecord::RecordInvalid => e
      redirect_to @purchase_order, alert: "Could not process payment: #{e.message}"
    rescue StandardError => e
      redirect_to @purchase_order, alert: "Error: #{e.message}"
    end
  end

  # VMCOTT WORK ORDER ACTIONS
  def mark_work_in_progress
    if @purchase_order.mark_work_in_progress!(current_user)
      redirect_to @purchase_order, notice: 'Work started successfully.'
    else
      redirect_to @purchase_order, alert: 'Could not start work.'
    end
  end

  def mark_internal_work_completed
    if @purchase_order.mark_internal_work_completed!(current_user)
      redirect_to @purchase_order, notice: 'Work marked as completed successfully.'
    else
      redirect_to @purchase_order, alert: 'Could not mark work as completed.'
    end
  end

  def mark_ready_for_delivery
    if @purchase_order.mark_ready_for_delivery!(current_user)
      redirect_to @purchase_order, notice: 'Marked as ready for delivery.'
    else
      redirect_to @purchase_order, alert: 'Could not mark as ready for delivery.'
    end
  end

  def mark_delivered
    if @purchase_order.mark_delivered!(current_user)
      PurchaseOrderMailer.po_delivered(@purchase_order).deliver_later if defined?(PurchaseOrderMailer)
      redirect_to @purchase_order, notice: 'Marked as delivered successfully. Agency notified.'
    else
      redirect_to @purchase_order, alert: 'Could not mark as delivered.'
    end
  end

  # LEGACY ACTIONS
  def approve
    redirect_to @purchase_order, alert: 'This action is no longer used. POs go directly to vendors.'
  end

  def reject
    redirect_to @purchase_order, alert: 'This action is no longer used. Please contact procurement.'
  end

  def cancel
    if @purchase_order.cancel!(params[:cancellation_reason])
      @purchase_order.payable&.update(status: 'cancelled') if @purchase_order.respond_to?(:payable)
      redirect_to @purchase_order, notice: 'Cancelled successfully.'
    else
      redirect_to @purchase_order, alert: 'Could not cancel purchase order.'
    end
  end

  def mark_ordered
    redirect_to @purchase_order, alert: 'Use "Send to Vendor" instead.'
  end

  def mark_received_legacy
    redirect_to @purchase_order, alert: 'Use "Mark as Received" instead.'
  end

  def payment
    unless @purchase_order.can_initiate_payment?
      redirect_to @purchase_order, alert: 'This purchase order cannot be paid at this time.'
    end
  end

  def process_payment
    card_details = {
      number: params[:card_number],
      expiry_month: params[:expiry_month],
      expiry_year: params[:expiry_year],
      cvv: params[:cvv],
      card_holder: params[:card_holder],
      card_type: params[:card_type],
      card_brand: params[:card_brand],
      last_four: params[:card_number]&.gsub(/\s+/, '')&.last(4)
    }

    billing_address = {
      line1: params[:billing_address_line1],
      line2: params[:billing_address_line2],
      city: params[:billing_city],
      state: params[:billing_state],
      postal_code: params[:billing_postal_code],
      country: 'Trinidad and Tobago'
    }

    if @purchase_order.initiate_trinidad_card_payment!(current_user, card_details, billing_address)
      redirect_to @purchase_order, notice: 'Payment initiated successfully. Waiting for authorization.'
    else
      flash.now[:alert] = @purchase_order.errors.full_messages.to_sentence
      render :payment
    end
  end

  def authorize_payment
    if @purchase_order.authorize_trinidad_payment!(current_user)
      redirect_to @purchase_order, notice: 'Payment authorized successfully. Processing payment.'
    else
      redirect_to @purchase_order, alert: 'Could not authorize payment.'
    end
  end

  def complete_payment
    if @purchase_order.complete_trinidad_payment!
      payable = @purchase_order.respond_to?(:payable) ? @purchase_order.payable : nil
      payable&.record_payment(@purchase_order.amount, @purchase_order.payment_method, @purchase_order.payment_reference)
      redirect_to @purchase_order, notice: 'Payment completed successfully.'
    else
      redirect_to @purchase_order, alert: 'Could not complete payment.'
    end
  end

  def record_payment
    payable = @purchase_order.respond_to?(:payable) ? @purchase_order.payable : nil
    unless payable
      redirect_to @purchase_order, alert: 'No payable record found for this purchase order.'
      return
    end

    payment_params = params.require(:payment).permit(:amount, :payment_method, :reference_number, :payment_date, :notes)

    if payable.record_payment(
      payment_params[:amount].to_d,
      payment_params[:payment_method],
      payment_params[:reference_number],
      Date.parse(payment_params[:payment_date] || Date.current.to_s)
    )
      @purchase_order.update(payment_status: 'completed', paid_at: Time.current) if payable.amount_due <= 0
      redirect_to @purchase_order, notice: 'Payment recorded successfully.'
    else
      flash.now[:alert] = 'Failed to record payment.'
      render :show, status: :unprocessable_entity
    end
  end

  def payment_summary
    @payable = @purchase_order.respond_to?(:payable) ? @purchase_order.payable : nil
    @account_transactions = @payable&.account_transactions || []
  end

  def payment_audits
    @payment_audits = @purchase_order.payment_audits.order(created_at: :desc)
    render partial: 'payment_audits' if request.xhr?
  end

  def convert_to_invoice
    if @purchase_order.invoices.exists?
      redirect_to @purchase_order, alert: 'An invoice already exists for this purchase order.'
      return
    end

    @invoice = @purchase_order.invoices.create!(
      invoice_number: "INV-#{@purchase_order.po_number}",
      vendor: @purchase_order.vendor,
      amount: @purchase_order.amount,
      status: 'paid',
      invoice_date: Date.current,
      due_date: Date.current,
      vehicle_id: @purchase_order.vehicle_id,
      created_by: current_user,
      notes: "Converted from Purchase Order #{@purchase_order.po_number}"
    )

    redirect_to @invoice, notice: 'Purchase order converted to invoice successfully.'
  rescue => e
    redirect_to @purchase_order, alert: "Could not convert to invoice: #{e.message}"
  end

  def print
    @purchase_order_items = @purchase_order.purchase_order_items

    respond_to do |format|
      format.html { render :print }
      format.pdf do
        begin
          if @purchase_order.respond_to?(:to_pdf)
            pdf = @purchase_order.to_pdf
            send_data pdf, filename: @purchase_order.pdf_filename, type: 'application/pdf', disposition: 'inline'
          else
            render pdf: "PO-#{@purchase_order.po_number}",
                   template: 'purchase_orders/print',
                   layout: 'pdf',
                   formats: [:html],
                   encoding: 'UTF-8',
                   show_as_html: params[:debug].present?
          end
        rescue => e
          Rails.logger.error "PDF generation failed: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")

          if request.format.pdf?
            redirect_to print_purchase_order_path(@purchase_order, format: :html),
                        alert: "PDF generation failed: #{e.message}. Showing HTML version instead."
          else
            render :print
          end
        end
      end
    end
  end

  def reports
    @start_date = (params[:start_date] || 30.days.ago.to_date)
    @end_date = (params[:end_date] || Date.today)
    @agency_id = params[:agency_id]
    @vendor = params[:vendor]
    @status = params[:status]

    @purchase_orders = PurchaseOrder.joins(:vehicle)
                                    .where(created_at: @start_date.beginning_of_day..@end_date.end_of_day)
    @purchase_orders = @purchase_orders.where(vehicles: { agency_id: @agency_id }) if @agency_id.present?
    @purchase_orders = @purchase_orders.where('vendor ILIKE ?', "%#{@vendor}%") if @vendor.present?
    @purchase_orders = @purchase_orders.where(status: @status) if @status.present?

    @summary = {
      total_orders: @purchase_orders.count,
      total_amount: @purchase_orders.sum(:amount),
      by_status: @purchase_orders.group(:status).count,
      by_payment_status: @purchase_orders.group(:payment_status).count,
      unpaid_amount: @purchase_orders.where(payment_status: ['unpaid', 'failed']).sum(:amount),
      vendors: @purchase_orders.group(:vendor).count
    }
  end

  def export
    @purchase_orders = fetch_purchase_orders
    respond_to do |format|
      format.csv { send_data @purchase_orders.to_csv, filename: "purchase_orders-#{Date.today}.csv" }
    end
  end

  def pending_approval
    redirect_to purchase_orders_path, alert: 'No pending approval - POs go directly to vendors.'
  end

  def bulk_approve
    redirect_to purchase_orders_path, alert: 'No bulk approval - POs go directly to vendors.'
  end

  def analytics
    @time_range = params[:time_range] || '30_days'
    @agency_id = params[:agency_id]

    @start_date =
      case @time_range
      when '7_days' then 7.days.ago
      when '30_days' then 30.days.ago
      when '90_days' then 90.days.ago
      when 'custom' then (Date.parse(params[:start_date]) if params[:start_date].present?)
      end

    @end_date = (Date.parse(params[:end_date]) if @time_range == 'custom' && params[:end_date].present?) || Time.current
    @start_date ||= 30.days.ago

    @stats = PurchaseOrder.trinidad_payment_stats(time_range: @start_date..@end_date, agency_id: @agency_id)
    @agencies = Agency.all if current_user.admin? || current_user.finance?
  end

  def reconciliation
    @start_date = params[:start_date] || Date.current.beginning_of_month
    @end_date = params[:end_date] || Date.current
    @agency_id = params[:agency_id]
    @agencies = Agency.all if current_user.admin? || current_user.finance?
  end

  def compliance_reports
    @purchase_orders = PurchaseOrder.trinidad_card_payments.order(created_at: :desc).page(params[:page]).per(20)
    @purchase_orders = @purchase_orders.joins(:vehicle).where(vehicles: { agency_id: params[:agency_id] }) if params[:agency_id].present?
    @agencies = Agency.all if current_user.admin? || current_user.finance?
  end

  def vendor_analysis
    @vendor = params[:vendor]

    if @vendor.present?
      @purchase_orders = PurchaseOrder.trinidad_card_payments.where(vendor: @vendor).order(created_at: :desc).page(params[:page]).per(20)
    end

    @top_vendors = PurchaseOrder.trinidad_card_payments.group(:vendor).order('sum_amount desc').limit(10).sum(:amount)
  end

  def export_reconciliation
    @purchase_orders = fetch_purchase_orders
    
    respond_to do |format|
      format.csv { send_data @purchase_orders.to_csv, filename: "reconciliation-#{Date.today}.csv" }
      format.xlsx { send_data @purchase_orders.to_xlsx, filename: "reconciliation-#{Date.today}.xlsx" }
      format.html { redirect_to reconciliation_purchase_orders_path, alert: 'Export feature coming soon' }
    end
  end

  def needs_payment
    @purchase_orders = PurchaseOrder.needs_payment
                                    .joins(:vehicle)
                                    .where(vehicles: { agency_id: current_user.agency_id })
                                    .recent
                                    .page(params[:page])
                                    .per(20)
    render :index
  end

  private

  def set_purchase_order
    @purchase_order =
      PurchaseOrder.includes(
        :vehicle,
        :created_by,
        :approved_by,
        :rejected_by,
        :supplier,
        :payable,
        :invoices,
        :payment_histories,
        :payment_audits,
        purchase_order_items: [:part]
      ).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to purchase_orders_path, alert: 'Purchase order not found.'
  end

  def redirect_pdf_to_print
    if request.format.pdf?
      redirect_to print_purchase_order_path(@purchase_order, format: :pdf)
    end
  end

  def fetch_purchase_orders
    base_scope = PurchaseOrder.recent.includes(:vehicle, :created_by, :approved_by)
    base_scope = base_scope.includes(:payable) if PurchaseOrder.reflect_on_association(:payable)

    if current_user.admin?
      base_scope = base_scope.all
    elsif current_user.agency&.code == 'VMCOTT'
      base_scope = base_scope.where(vendor: 'VMCOTT')
    else
      base_scope = base_scope.joins(:vehicle).where(vehicles: { agency_id: current_user.agency_id })
    end

    base_scope = base_scope.where(status: params[:status]) if params[:status].present?
    base_scope = base_scope.where(payment_status: params[:payment_status]) if params[:payment_status].present?
    base_scope = base_scope.where(created_by_id: params[:created_by]) if params[:created_by].present?
    base_scope = base_scope.where(payment_method: params[:payment_method]) if params[:payment_method].present?
    base_scope = base_scope.where('created_at >= ?', params[:date_from]) if params[:date_from].present?
    base_scope = base_scope.where('created_at <= ?', params[:date_to]) if params[:date_to].present?
    base_scope = base_scope.where('vendor ILIKE ?', "%#{params[:vendor]}%") if params[:vendor].present?

    base_scope.page(params[:page]).per(20)
  end

  def purchase_order_params
    params.require(:purchase_order).permit(
      :vehicle_id, :vendor, :amount, :notes, :payment_terms,
      purchase_order_items_attributes: [
        :id, :part_id, :description, :quantity, :unit_price, :total_price,
        :is_accepted, :rejection_reason, :_destroy
      ]
    )
  end

  def check_edit_permission
    redirect_to @purchase_order, alert: 'This purchase order cannot be edited.' unless @purchase_order.editable?
  end

  def require_finance
    redirect_to root_path, alert: 'Unauthorized - Finance access required' unless current_user.finance? || current_user.admin?
  end

  def calculate_accepted_total(quotation)
    quotation.amount.to_f
  end

  def generate_po_number
    "PO-#{Time.now.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
  end

  # Notification methods
  def notify_inventory_manager(purchase_order)
    inventory_managers = User.where(role: 'inventory_manager').pluck(:email)
    return unless inventory_managers.any?
    
    PurchaseOrderMailer.stock_received(purchase_order, inventory_managers).deliver_later if defined?(PurchaseOrderMailer)
    Rails.logger.info "📦 Inventory Manager notified about received parts for PO #{purchase_order.po_number}"
  end

  def notify_workshop(purchase_order)
    workshop_users = User.where(role: 'workshop_supervisor').pluck(:email)
    return unless workshop_users.any?
    
    PurchaseOrderMailer.parts_available(purchase_order, workshop_users).deliver_later if defined?(PurchaseOrderMailer)
    Rails.logger.info "🔧 Workshop notified about available parts for PO #{purchase_order.po_number}"
  end

  def notify_finance(purchase_order)
    finance_users = User.where(role: 'finance').pluck(:email)
    return unless finance_users.any?
    
    PurchaseOrderMailer.ready_for_payment(purchase_order, finance_users).deliver_later if defined?(PurchaseOrderMailer)
    Rails.logger.info "💰 Finance notified about payment readiness for PO #{purchase_order.po_number}"
  end
end