# app/controllers/suppliers_controller.rb - NEW FILE
class SuppliersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_supplier, only: [:show, :edit, :update, :destroy, :invoices, :upload_invoice]
  
  def index
    @suppliers = Supplier.active.order(:name)
    
    if params[:search].present?
      @suppliers = @suppliers.search(params[:search])
    end
  end
  
  def show
    @vendor_invoices = @supplier.vendor_invoices.includes(:purchase_order).order(invoice_date: :desc)
    @purchase_orders = @supplier.purchase_orders.order(created_at: :desc)
    @parts = @supplier.parts.order(:name)
    
    # Statistics
    @total_spent = @supplier.paid_amount
    @outstanding = @supplier.total_outstanding
    @overdue_invoices = @supplier.vendor_invoices.overdue
  end
  
  def new
    @supplier = Supplier.new
  end
  
  def create
    @supplier = Supplier.new(supplier_params)
    
    if @supplier.save
      redirect_to @supplier, notice: 'Vendor was successfully created.'
    else
      render :new
    end
  end
  
  def edit
  end
  
  def update
    if @supplier.update(supplier_params)
      redirect_to @supplier, notice: 'Vendor was successfully updated.'
    else
      render :edit
    end
  end
  
  def destroy
    @supplier.update(is_active: false)
    redirect_to suppliers_path, notice: 'Vendor was deactivated.'
  end
  
  def invoices
    @vendor_invoices = @supplier.vendor_invoices.includes(:purchase_order)
    
    # Search functionality
    if params[:q].present?
      @vendor_invoices = @vendor_invoices.search(params[:q])
    end
    
    if params[:start_date].present? && params[:end_date].present?
      @vendor_invoices = @vendor_invoices.by_date_range(
        Date.parse(params[:start_date]),
        Date.parse(params[:end_date])
      )
    end
    
    respond_to do |format|
      format.html
      format.json { render json: @vendor_invoices }
    end
  end
  
  def upload_invoice
    @vendor_invoice = @supplier.vendor_invoices.new(vendor_invoice_params)
    @vendor_invoice.user = current_user
    
    if @vendor_invoice.save
      # Attach scanned invoice if provided
      if params[:vendor_invoice][:invoice_scan].present?
        @vendor_invoice.invoice_scan.attach(params[:vendor_invoice][:invoice_scan])
      end
      
      # Process linked purchase order
      process_linked_purchase_order(@vendor_invoice)
      
      redirect_to supplier_path(@supplier), 
                  notice: "Invoice #{@vendor_invoice.invoice_number} uploaded successfully."
    else
      flash[:alert] = "Failed to upload invoice: #{@vendor_invoice.errors.full_messages.join(', ')}"
      render :show
    end
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
  
  def process_linked_purchase_order(invoice)
    return unless invoice.purchase_order
    
    # Update inventory for each item in the PO
    invoice.purchase_order.purchase_order_items.each do |item|
      if item.part
        item.part.update_from_vendor_invoice(
          item.quantity,
          item.unit_price,
          invoice
        )
      end
    end
  end
end
