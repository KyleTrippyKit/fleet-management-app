# app/controllers/vendor_invoices_controller.rb
class VendorInvoicesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_vendor_invoice, only: [:show, :mark_paid, :mark_reviewed, :dispute, :destroy]
  before_action :require_vmcott_user
  
  def index
    @vendor_invoices = VendorInvoice.includes(:supplier, :purchase_order)
      .order(invoice_date: :desc)
      .page(params[:page])
      .per(20)
    
    # Search
    if params[:q].present?
      @vendor_invoices = @vendor_invoices.where(
        "invoice_number ILIKE ? OR vendor_invoices.description ILIKE ?", 
        "%#{params[:q]}%", "%#{params[:q]}%"
      )
    end
    
    # Filter by supplier
    if params[:supplier_id].present?
      @vendor_invoices = @vendor_invoices.where(supplier_id: params[:supplier_id])
    end
    
    # Filter by status
    if params[:status].present?
      @vendor_invoices = @vendor_invoices.where(status: params[:status])
    end
    
    # Date range filter
    if params[:start_date].present? && params[:end_date].present?
      start_date = Date.parse(params[:start_date])
      end_date = Date.parse(params[:end_date])
      @vendor_invoices = @vendor_invoices.where(invoice_date: start_date..end_date)
    end
  end
  
  def show
    respond_to do |format|
      format.html
      format.json { render json: @vendor_invoice }
    end
  end
  
  def create
    @vendor_invoice = VendorInvoice.new(vendor_invoice_params)
    @vendor_invoice.user = current_user
    
    if @vendor_invoice.save
      # Attach scanned invoice if provided
      if params[:vendor_invoice][:invoice_scan].present?
        @vendor_invoice.invoice_scan.attach(params[:vendor_invoice][:invoice_scan])
      end
      
      redirect_to vendor_invoice_path(@vendor_invoice), 
                  notice: 'Vendor invoice was successfully created.'
    else
      flash[:alert] = "Failed to create invoice: #{@vendor_invoice.errors.full_messages.join(', ')}"
      redirect_back(fallback_location: suppliers_path)
    end
  end
  
  def destroy
    @vendor_invoice.destroy
    redirect_to vendor_invoices_url, notice: 'Vendor invoice was successfully deleted.'
  end
  
  def mark_paid
    payment_date = params[:paid_date] ? Date.parse(params[:paid_date]) : Date.today
    payment_notes = params[:payment_notes]
    payment_method = params[:payment_method] || 'bank_transfer'
    
    if @vendor_invoice.mark_as_paid(payment_date, payment_notes)
      # Create payment transaction
      Transaction.create!(
        amount: @vendor_invoice.amount,
        description: "Payment for vendor invoice #{@vendor_invoice.invoice_number}",
        transaction_type: 'payment',
        payment_method: payment_method,
        reference_number: "PAY-#{SecureRandom.hex(6).upcase}",
        status: 'completed',
        user: current_user
      )
      
      redirect_to @vendor_invoice, notice: 'Invoice marked as paid.'
    else
      flash[:alert] = "Failed to mark invoice as paid: #{@vendor_invoice.errors.full_messages.join(', ')}"
      redirect_to @vendor_invoice
    end
  end
  
  def mark_reviewed
    @vendor_invoice.update!(status: 'reviewed')
    redirect_to @vendor_invoice, notice: 'Invoice marked as reviewed.'
  end
  
  def dispute
    @vendor_invoice.update!(status: 'disputed')
    redirect_to @vendor_invoice, notice: 'Invoice marked as disputed.'
  end
  
  def search
    query = params[:q].to_s.strip
    
    @vendor_invoices = VendorInvoice.joins(:supplier)
      .where("invoice_number ILIKE ? OR vendor_invoices.description ILIKE ? OR suppliers.name ILIKE ?",
             "%#{query}%", "%#{query}%", "%#{query}%")
      .order(invoice_date: :desc)
      .limit(20)
    
    render json: @vendor_invoices.map { |vi| 
      { 
        id: vi.id, 
        invoice_number: vi.invoice_number,
        invoice_date: vi.invoice_date.strftime("%Y-%m-%d"),
        amount: vi.amount,
        supplier_name: vi.supplier.name,
        status: vi.status,
        due_date: vi.due_date ? vi.due_date.strftime("%Y-%m-%d") : nil
      }
    }
  end
  
  def aging_report
    @aging_report = VendorInvoice.all.group_by(&:aging_bucket)
    @total_outstanding = VendorInvoice.where(status: ['pending', 'reviewed']).sum(:amount)
  end
  
  def bulk_approve
    invoice_ids = params[:invoice_ids] || []
    
    if invoice_ids.present?
      count = VendorInvoice.where(id: invoice_ids).update_all(status: 'reviewed')
      flash[:notice] = "Marked #{count} invoices as reviewed."
    else
      flash[:alert] = "No invoices selected."
    end
    
    redirect_to vendor_invoices_path
  end
  
  private
  
  def set_vendor_invoice
    @vendor_invoice = VendorInvoice.find(params[:id])
  end
  
  def vendor_invoice_params
    params.require(:vendor_invoice).permit(
      :supplier_id, :purchase_order_id, :invoice_number, 
      :invoice_date, :due_date, :amount, :currency, 
      :description
    )
  end
  
  def require_vmcott_user
    return if current_user.admin?
    
    unless current_user.agency&.code == 'VMCOTT'
      redirect_to root_path, alert: 'Access denied. VMCOTT users only.'
    end
  end
end