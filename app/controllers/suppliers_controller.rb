# app/controllers/suppliers_controller.rb
class SuppliersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_supplier, only: [:show, :edit, :update, :destroy, :invoices, :upload_invoice, 
                                      :update_stock, :process_stock_update, :inventory_items, :new_item_form]
  before_action :require_vmcott_user, except: [:index, :show, :search]
  
  # GET /suppliers
  def index
    @suppliers = Supplier.active.order(name: :asc)
    
    if params[:search].present?
      @suppliers = @suppliers.where("name ILIKE ? OR email ILIKE ? OR phone ILIKE ?", 
                                   "%#{params[:search]}%", "%#{params[:search]}%", "%#{params[:search]}%")
    end
    
    respond_to do |format|
      format.html
      format.json { render json: @suppliers }
    end
  end
  
  # GET /suppliers/1
  def show
    @vendor_invoices = @supplier.vendor_invoices.includes(:purchase_order).order(invoice_date: :desc).limit(10)
    @purchase_orders = @supplier.purchase_orders.order(created_at: :desc).limit(5)
    @parts = @supplier.parts.order(:name)
    
    # Statistics
    @total_spent = @supplier.vendor_invoices.where(status: 'paid').sum(:amount)
    @outstanding = @supplier.vendor_invoices.where(status: ['pending', 'reviewed']).sum(:amount)
    @overdue_invoices = @supplier.vendor_invoices.where("due_date < ? AND status IN (?)", 
      Date.today, ['pending', 'reviewed'])
    
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
  
  # GET /suppliers/1/invoices
  def invoices
    @vendor_invoices = @supplier.vendor_invoices
      .includes(:purchase_order)
      .order(invoice_date: :desc)
      .page(params[:page])
      .per(20)
    
    if params[:q].present?
      @vendor_invoices = @vendor_invoices.where("invoice_number ILIKE ?", "%#{params[:q]}%")
    end
    
    if params[:start_date].present? && params[:end_date].present?
      start_date = Date.parse(params[:start_date])
      end_date = Date.parse(params[:end_date])
      @vendor_invoices = @vendor_invoices.where(invoice_date: start_date..end_date)
    end
  end
  
  # POST /suppliers/1/upload_invoice
  def upload_invoice
    @vendor_invoice = @supplier.vendor_invoices.new(vendor_invoice_params)
    @vendor_invoice.user = current_user
    
    if @vendor_invoice.save
      # Attach scanned invoice if provided
      if params[:vendor_invoice][:invoice_scan].present?
        @vendor_invoice.invoice_scan.attach(params[:vendor_invoice][:invoice_scan])
      end
      
      # If linked to PO, update inventory
      if @vendor_invoice.purchase_order
        update_inventory_from_invoice(@vendor_invoice)
      end
      
      redirect_to supplier_path(@supplier), 
                  notice: "Invoice #{@vendor_invoice.invoice_number} uploaded successfully."
    else
      flash[:alert] = "Failed to upload invoice: #{@vendor_invoice.errors.full_messages.join(', ')}"
      render :show
    end
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
      .where("name ILIKE ? OR email ILIKE ? OR phone ILIKE ? OR contact_person ILIKE ?",
             "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%")
      .limit(10)
      .order(:name)
    
    render json: @suppliers.map { |s| 
      { 
        id: s.id, 
        name: s.name, 
        email: s.email,
        phone: s.phone,
        outstanding: s.total_outstanding
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
      :payment_terms, :notes, :is_active
    )
  end
  
  def vendor_invoice_params
    params.require(:vendor_invoice).permit(
      :invoice_number, :invoice_date, :amount, :currency,
      :description, :purchase_order_id, :due_date
    )
  end
  
  def update_inventory_from_invoice(invoice)
    return unless invoice.purchase_order
    
    invoice.purchase_order.purchase_order_items.each do |item|
      next unless item.part
      
      # Update part stock
      item.part.update!(
        current_stock: item.part.current_stock + item.quantity,
        cost_price: item.unit_price
      )
      
      # Create inventory transaction
      InventoryTransaction.create!(
        inventory_item: item.part,
        transaction_type: 'receipt',
        quantity: item.quantity,
        unit_price: item.unit_price,
        total_price: item.total_price,
        notes: "Received via vendor invoice #{invoice.invoice_number}",
        vendor_invoice: invoice,
        user: current_user
      )
    end
  end
  
  def require_vmcott_user
    return if current_user.admin?
    
    unless current_user.agency&.code == 'VMCOTT'
      redirect_to root_path, alert: 'Access denied. VMCOTT users only.'
    end
  end
end