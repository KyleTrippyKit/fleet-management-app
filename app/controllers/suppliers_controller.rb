class SuppliersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_supplier, only: [:show, :edit, :update, :destroy, :invoices, :upload_invoice, 
                                      :new_invoice, :process_invoice, :update_stock, :process_stock_update, 
                                      :inventory_items, :new_item_form]
  before_action :require_vmcott_user, except: [:index, :show, :search]
  
  # GET /suppliers - CARD VIEW
  def index
    @suppliers = Supplier.active.includes(:vendor_invoices).order(name: :asc)
    
    if params[:search].present?
      search_term = "%#{params[:search]}%"
      @suppliers = @suppliers.where(
        "suppliers.name ILIKE ? OR suppliers.email ILIKE ? OR suppliers.contact_person ILIKE ? OR suppliers.phone ILIKE ?",
        search_term, search_term, search_term, search_term
      )
    end
    
    # Pre-calculate stats for each supplier to avoid N+1 queries
    @suppliers_with_stats = @suppliers.map do |supplier|
      {
        supplier: supplier,
        total_spent: supplier.vendor_invoices.where(status: 'paid').sum(:amount),
        outstanding: supplier.vendor_invoices.where(status: ['pending', 'reviewed']).sum(:amount),
        invoice_count: supplier.vendor_invoices.count,
        last_invoice: supplier.vendor_invoices.order(invoice_date: :desc).first
      }
    end
    
    respond_to do |format|
      format.html
      format.json { render json: @suppliers }
    end
  end
  
  # GET /suppliers/1 - VENDOR DETAIL PAGE WITH STATS
  def show
    @vendor_invoices = @supplier.vendor_invoices.includes(:purchase_order).order(invoice_date: :desc).limit(10)
    @purchase_orders = @supplier.purchase_orders.order(created_at: :desc).limit(5)
    @parts = @supplier.parts.order(:name)
    
    # Statistics
    @total_spent = @supplier.vendor_invoices.where(status: 'paid').sum(:amount)
    @outstanding = @supplier.vendor_invoices.where(status: ['pending', 'reviewed']).sum(:amount)
    @overdue_invoices = @supplier.vendor_invoices.where("due_date < ? AND status IN (?)", 
      Date.today, ['pending', 'reviewed'])
    @invoice_count = @supplier.vendor_invoices.count
    
    # For new invoice form
    @vendor_invoice = @supplier.vendor_invoices.new
    @vendor_invoice.invoice_date = Date.today
    @vendor_invoice.due_date = Date.today + 30.days
  end
  
  # GET /suppliers/new
  def new
    @supplier = Supplier.new
  end
  
  # GET /suppliers/1/edit
  def edit
  end
  
  # POST /suppliers
  def create
    @supplier = Supplier.new(supplier_params)
    
    if @supplier.save
      redirect_to @supplier, notice: 'Supplier was successfully created.'
    else
      render :new
    end
  end
  
  # PATCH/PUT /suppliers/1
  def update
    if @supplier.update(supplier_params)
      redirect_to @supplier, notice: 'Supplier was successfully updated.'
    else
      render :edit
    end
  end
  
  # DELETE /suppliers/1
  def destroy
    @supplier.update(is_active: false)
    redirect_to suppliers_url, notice: 'Supplier was deactivated.'
  end
  
  # GET /suppliers/1/invoices - INVOICE LIST WITH SEARCH
  def invoices
    @vendor_invoices = @supplier.vendor_invoices
      .includes(:purchase_order)
      .order(invoice_date: :desc)
      .page(params[:page])
      .per(20)
    
    # Calculate stats for display
    @outstanding = @vendor_invoices.where(status: ['pending', 'reviewed']).sum(:amount)
    @paid = @vendor_invoices.where(status: 'paid').sum(:amount)
    @total = @vendor_invoices.sum(:amount)
    
    # FIXED: Enhanced search - search by ID, invoice number, or date
    if params[:search].present?
      search_term = "%#{params[:search]}%"
      @vendor_invoices = @vendor_invoices.where(
        "invoice_number ILIKE ? OR CAST(vendor_invoices.id AS TEXT) ILIKE ? OR description ILIKE ?",
        search_term, search_term, search_term
      )
    end
    
    # Status filter
    if params[:status].present?
      @vendor_invoices = @vendor_invoices.where(status: params[:status])
    end
    
    # Date range filter - FIXED: Handle single dates too
    if params[:start_date].present?
      start_date = Date.parse(params[:start_date])
      if params[:end_date].present?
        end_date = Date.parse(params[:end_date])
        @vendor_invoices = @vendor_invoices.where(invoice_date: start_date..end_date)
      else
        @vendor_invoices = @vendor_invoices.where(invoice_date: start_date)
      end
    end
    
    respond_to do |format|
      format.html
      format.json do
        render json: @vendor_invoices.limit(20).map { |vi|
          {
            id: vi.id,
            invoice_number: vi.invoice_number,
            invoice_date: vi.invoice_date,
            amount: vi.amount,
            status: vi.status,
            purchase_order_id: vi.purchase_order_id,
            due_date: vi.due_date,
            has_attachment: vi.invoice_scan.attached?,
            attachment_url: vi.invoice_scan.attached? ? rails_blob_url(vi.invoice_scan) : nil
          }
        }
      end
    end
  end
  
  # GET /suppliers/1/new_invoice - NEW INVOICE FORM
  def new_invoice
    @vendor_invoice = @supplier.vendor_invoices.new
    @vendor_invoice.invoice_date = Date.today
    @vendor_invoice.due_date = Date.today + 30.days
    
    # Get available purchase orders for this supplier
    @purchase_orders = @supplier.purchase_orders.where(status: ['approved', 'ordered'])
    
    # Return just the modal HTML for AJAX requests
    if request.xhr?
      render partial: 'new_invoice_modal', layout: false
    else
      render 'new_invoice', layout: false
    end
  end
  
  # POST /suppliers/1/upload_invoice - FIXED FILE UPLOAD
  def upload_invoice
    @vendor_invoice = @supplier.vendor_invoices.new(vendor_invoice_params)
    @vendor_invoice.user = current_user
    
    invoice_scan_file = params[:vendor_invoice][:invoice_scan] if params[:vendor_invoice]
    
    if @vendor_invoice.valid?
      begin
        ActiveRecord::Base.transaction do
          @vendor_invoice.save!
          
          if invoice_scan_file.present?
            @vendor_invoice.invoice_scan.attach(invoice_scan_file)
          end
          
          if @vendor_invoice.purchase_order
            update_inventory_from_po(@vendor_invoice.purchase_order, @vendor_invoice)
          end
        end
        
        # MOVE AUDIT LOG OUTSIDE TRANSACTION
        create_invoice_audit(@vendor_invoice, 'uploaded')
        
        redirect_to invoices_supplier_path(@supplier), 
                    notice: "Invoice #{@vendor_invoice.invoice_number} uploaded successfully."
      rescue => e
        flash[:alert] = "Failed to upload invoice: #{e.message}"
        @purchase_orders = @supplier.purchase_orders.where(status: ['approved', 'ordered'])
        render :new_invoice, layout: false
      end
    else
      @purchase_orders = @supplier.purchase_orders.where(status: ['approved', 'ordered'])
      flash[:alert] = "Failed to upload invoice: #{@vendor_invoice.errors.full_messages.join(', ')}"
      render :new_invoice, layout: false
    end
  end
  
  # POST /suppliers/1/process_invoice - PROCESS INVOICE PAYMENT/STATUS
  def process_invoice
    @vendor_invoice = @supplier.vendor_invoices.find(params[:invoice_id])
    action = params[:action_type]
    
    case action
    when 'mark_paid'
      @vendor_invoice.mark_as_paid(Date.today, params[:payment_notes])
      message = "Invoice marked as paid."
    when 'mark_reviewed'
      @vendor_invoice.update!(status: 'reviewed')
      message = "Invoice marked as reviewed."
    when 'dispute'
      @vendor_invoice.update!(status: 'disputed', payment_notes: params[:dispute_reason])
      message = "Invoice marked as disputed."
    else
      return redirect_to invoices_supplier_path(@supplier), alert: "Invalid action."
    end
    
    # Create audit log for the action
    create_invoice_audit(@vendor_invoice, action)
    
    redirect_to invoices_supplier_path(@supplier), notice: message
  end
  
  # GET /suppliers/1/update_stock
  def update_stock
    @parts = @supplier.parts.order(:name)
    
    if params[:search].present?
      @parts = @parts.where("name ILIKE ? OR part_number ILIKE ?", 
                           "%#{params[:search]}%", "%#{params[:search]}%")
    end
  end
  
  # POST /suppliers/1/process_stock_update
  def process_stock_update
    if params[:adjustments].present?
      ActiveRecord::Base.transaction do
        params[:adjustments].each do |part_id, adjustment|
          next if adjustment[:quantity].blank? || adjustment[:quantity].to_i == 0
          
          part = Part.find(part_id)
          quantity = adjustment[:quantity].to_i
          notes = adjustment[:notes].presence || "Manual stock update"
          
          # Update stock
          new_stock = part.current_stock + quantity
          part.update!(current_stock: new_stock)
          
          # Create inventory transaction
          InventoryTransaction.create!(
            inventory_item: part,
            transaction_type: quantity > 0 ? 'receipt' : 'issue',
            quantity: quantity.abs,
            unit_price: part.cost_price || 0,
            total_price: quantity.abs * (part.cost_price || 0),
            notes: "#{notes} - via supplier interface",
            user: current_user
          )
          
          # Create purchase request if stock is critically low after adjustment
          if new_stock <= part.minimum_stock && quantity < 0
            shortage = part.reorder_point - new_stock
            if shortage > 0
              PurchaseRequest.create!(
                part: part,
                quantity: shortage,
                urgency: 'high',
                requested_by: current_user,
                notes: "Auto-generated after stock adjustment. Current: #{new_stock}, Min: #{part.minimum_stock}"
              )
            end
          end
        end
      end
      
      redirect_to update_stock_supplier_path(@supplier), 
                  notice: 'Stock updated successfully.'
    else
      flash[:alert] = 'No adjustments were made.'
      redirect_to update_stock_supplier_path(@supplier)
    end
  end
  
  # GET /suppliers/1/inventory_items
  def inventory_items
    @parts = @supplier.parts.includes(:inventory_transactions).order(:name).page(params[:page]).per(20)
    
    if params[:search].present?
      @parts = @parts.where("name ILIKE ? OR part_number ILIKE ?", 
                           "%#{params[:search]}%", "%#{params[:search]}%")
    end
  end
  
  # GET /suppliers/1/new_item_form
  def new_item_form
    @part = @supplier.parts.new
    @categories = Part.distinct.pluck(:category).compact.sort
    
    render partial: 'inventory_items/form', locals: { supplier: @supplier, part: @part }
  end
  
  # GET /suppliers/search
  def search
    query = params[:q].to_s.strip
    
    @suppliers = Supplier.active
      .where("name ILIKE ? OR email ILIKE ? OR contact_person ILIKE ?", 
             "%#{query}%", "%#{query}%", "%#{query}%")
      .limit(10)
      .order(:name)
    
    render json: @suppliers.map { |s| 
      { 
        id: s.id, 
        name: s.name, 
        email: s.email,
        phone: s.phone,
        outstanding: s.vendor_invoices.where(status: ['pending', 'reviewed']).sum(:amount),
        contact_person: s.contact_person,
        is_active: s.is_active,
        vendor_invoice_count: s.vendor_invoices.count
      } 
    }
  end
  
  private
  
  def set_supplier
    @supplier = Supplier.find(params[:id])
  end
  
  def supplier_params
    params.require(:supplier).permit(
      :name, :address, :email, :phone, :contact_person,
      :payment_terms, :notes, :is_active,
      :tax_id, :website, :bank_account_details
    )
  end
  
  def vendor_invoice_params
    params.require(:vendor_invoice).permit(
      :invoice_number, :invoice_date, :amount, :currency,
      :description, :purchase_order_id, :due_date,
      :invoice_scan, :tax_amount, :shipping_cost
    )
  end
  
  def update_inventory_from_po(purchase_order, vendor_invoice)
    return unless purchase_order
    
    purchase_order.purchase_order_items.each do |po_item|
      next unless po_item.part
      
      # Check if already received via this invoice
      next if InventoryTransaction.exists?(
        vendor_invoice: vendor_invoice,
        inventory_item: po_item.part
      )
      
      # Update stock
      po_item.part.update!(
        current_stock: po_item.part.current_stock + po_item.quantity,
        cost_price: po_item.unit_price  # Update cost price from PO
      )
      
      # Create inventory transaction
      InventoryTransaction.create!(
        inventory_item: po_item.part,
        transaction_type: 'receipt',
        quantity: po_item.quantity,
        unit_price: po_item.unit_price,
        total_price: po_item.total_price,
        notes: "Received via PO #{purchase_order.po_number}, Invoice #{vendor_invoice.invoice_number}",
        vendor_invoice: vendor_invoice,
        purchase_order: purchase_order,
        user: current_user
      )
    end
  end
  
  def create_invoice_audit(vendor_invoice, action)
    # Create audit log for invoice actions
    # FIXED: Changed from `resource: vendor_invoice` to use `resource_type` and `resource_id`
    AccessLog.create!(
      user_id: current_user.id,
      action: "invoice_#{action}",
      resource_type: 'VendorInvoice',
      resource_id: vendor_invoice.id,
      details: {
        invoice_number: vendor_invoice.invoice_number,
        amount: vendor_invoice.amount,
        supplier_id: vendor_invoice.supplier_id,
        outcome: 'success'
      }.to_json,  # Convert hash to JSON string for text column
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      agency_id: current_user.agency_id,  # Use existing column
      accessed_at: Time.current  # Use existing column
    )
  rescue => e
    # Log error but don't break the main flow
    Rails.logger.error "Failed to create access log: #{e.message}"
  end
  
  def require_vmcott_user
    return if current_user.admin?
    
    unless current_user.agency&.code == 'VMCOTT'
      redirect_to root_path, alert: 'Access denied. VMCOTT users only.'
    end
  end
  
  # Helper method for view
  helper_method :invoice_status_color
  def invoice_status_color(status)
    case status
    when 'paid' then 'bg-green-100 text-green-800'
    when 'pending' then 'bg-yellow-100 text-yellow-800'
    when 'reviewed' then 'bg-blue-100 text-blue-800'
    when 'disputed' then 'bg-red-100 text-red-800'
    else 'bg-gray-100 text-gray-800'
    end
  end
end