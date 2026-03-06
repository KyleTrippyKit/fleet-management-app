# app/controllers/vmcott/billing/invoices_controller.rb
class Vmcott::Billing::InvoicesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_billing_officer
  before_action :set_invoice, only: [:show, :process_payment, :print]

  def index
    @invoices = Invoice.all.order(created_at: :desc)
    
    # Filter by status if provided
    if params[:status].present?
      @invoices = @invoices.where(status: params[:status])
    end
    
    # Filter by agency/vendor if provided
    if params[:vendor].present?
      @invoices = @invoices.where("vendor ILIKE ?", "%#{params[:vendor]}%")
    end
    
    # Get recent invoices for dashboard
    @recent_invoices = @invoices.limit(10)
    
    # Paginate
    @invoices = @invoices.page(params[:page]).per(20) if @invoices.respond_to?(:page)
    
    @stats = {
      total_pending: Invoice.where(status: 'pending').count,
      total_paid_this_month: Invoice.where(status: 'paid')
                                    .where('paid_at >= ?', Date.current.beginning_of_month)
                                    .count,
      total_outstanding: Invoice.where(status: ['pending', 'overdue']).sum(:amount)
    }
  end

  def show
    @invoice = Invoice.find(params[:id])
    @vehicle = @invoice.vehicle
    @agency = @vehicle&.agency
    @purchase_order = @invoice.purchase_order
    @work_orders = @purchase_order&.internal_pos if @purchase_order
  end

  def new
    # Get all completed POs ready for invoicing
    @purchase_orders = PurchaseOrder.where(status: ['approved', 'received', 'internal_work_completed', 'ready_for_delivery'])
                                    .where.not(vehicle_id: nil)
                                    .includes(vehicle: :agency)
                                    .order(created_at: :desc)
    
    # Get unique vendors from multiple sources
    po_vendors = PurchaseOrder.where.not(vendor: [nil, '']).distinct.pluck(:vendor)
    
    # Get vendor names from vehicles through their agencies
    vehicle_vendors = PurchaseOrder.joins(vehicle: :agency)
                                    .where.not(vehicles: { agency_id: nil })
                                    .distinct
                                    .pluck('agencies.name')
    
    agency_names = Agency.where.not(name: [nil, '']).distinct.pluck(:name)
    
    @vendors = (po_vendors + vehicle_vendors + agency_names).uniq.compact.sort
    
    # Check if we're coming from a specific purchase order
    if params[:purchase_order_id].present?
      @purchase_order = PurchaseOrder.find(params[:purchase_order_id])
      @invoice = Invoice.new(
        purchase_order: @purchase_order,
        vehicle_id: @purchase_order.vehicle_id,
        vehicle: @purchase_order.vehicle,
        vendor: @purchase_order.agency&.name || @purchase_order.vendor,
        amount: @purchase_order.amount,
        invoice_date: Date.current,
        due_date: Date.current + 30.days,
        status: 'pending'
      )
    else
      @invoice = Invoice.new(
        invoice_date: Date.current,
        due_date: Date.current + 30.days,
        status: 'pending'
      )
    end
  end

  def create
    @invoice = Invoice.new(invoice_params)
    @invoice.created_by = current_user
    @invoice.invoice_number ||= generate_invoice_number
    
    # Set vehicle_id from purchase_order if present
    if @invoice.purchase_order.present? && @invoice.vehicle_id.blank?
      @invoice.vehicle_id = @invoice.purchase_order.vehicle_id
    end
    
    # Set vendor to agency name if not specified
    if @invoice.vendor.blank? && @invoice.vehicle&.agency.present?
      @invoice.vendor = @invoice.vehicle.agency.name
    end
    
    if @invoice.save
      # Using 'ready_for_delivery' (valid status in enum)
      if @invoice.purchase_order.present?
        @invoice.purchase_order.update(vmcott_status: 'ready_for_delivery')
      end
      
      redirect_to vmcott_billing_invoice_path(@invoice), notice: "Invoice created successfully"
    else
      # Log errors for debugging
      Rails.logger.error "Invoice creation failed: #{@invoice.errors.full_messages.join(', ')}"
      
      # Reload form data for re-render
      @purchase_orders = PurchaseOrder.where(status: ['approved', 'received', 'internal_work_completed', 'ready_for_delivery'])
                                      .where.not(vehicle_id: nil)
                                      .includes(vehicle: :agency)
                                      .order(created_at: :desc)
      
      po_vendors = PurchaseOrder.where.not(vendor: [nil, '']).distinct.pluck(:vendor)
      vehicle_vendors = PurchaseOrder.joins(vehicle: :agency)
                                      .where.not(vehicles: { agency_id: nil })
                                      .distinct
                                      .pluck('agencies.name')
      agency_names = Agency.where.not(name: [nil, '']).distinct.pluck(:name)
      @vendors = (po_vendors + vehicle_vendors + agency_names).uniq.compact.sort
      
      render :new, status: :unprocessable_entity
    end
  end

  def process_payment
    @invoice = Invoice.find(params[:id])
    
    if @invoice.update(
      status: 'paid',
      paid_at: Time.current,
      paid_by: current_user
    )
      # Update associated purchase order
      if @invoice.purchase_order.present?
        @invoice.purchase_order.update(
          payment_status: 'completed',
          status: 'paid',
          paid_at: Time.current
        )
      end
      
      # ✅ OPTION 1: Create payment history with polymorphic association set to the invoice
      if defined?(PaymentHistory)
        payment_history = @invoice.payment_histories.create!(
          amount: @invoice.amount,
          payment_date: Date.current,
          payment_method: params[:payment_method].presence || 'bank_transfer',
          reference_number: params[:reference_number].presence || generate_payment_reference,
          status: 'completed',
          user: current_user,
          payment_transaction: @invoice  # Set the polymorphic association to the invoice itself
        )
        
        # Log success
        Rails.logger.info "Payment history created successfully for invoice #{@invoice.invoice_number}"
      end
      
      redirect_to vmcott_billing_invoice_path(@invoice), notice: "Payment processed successfully"
    else
      redirect_to vmcott_billing_invoice_path(@invoice), alert: "Could not process payment"
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Payment processing failed: #{e.message}"
    redirect_to vmcott_billing_invoice_path(@invoice), alert: "Payment processing failed: #{e.message}"
  end

  def print
    @invoice = Invoice.find(params[:id])
    @vehicle = @invoice.vehicle
    @agency = @vehicle&.agency
    @purchase_order = @invoice.purchase_order
    
    respond_to do |format|
      format.html { render layout: 'pdf' }  # For HTML preview/debug
      format.pdf do
        render pdf: "invoice-#{@invoice.invoice_number}",
               template: 'vmcott/billing/invoices/print',
               layout: 'pdf',
               formats: [:html],
               encoding: 'UTF-8',
               page_size: 'A4',
               margin: { top: 20, bottom: 20, left: 15, right: 15 },
               show_as_html: params[:debug].present?,
               header: {
                 html: {
                   template: 'shared/pdf/_header',
                   layout: false
                 }
               },
               footer: {
                 html: {
                   template: 'shared/pdf/_footer',
                   layout: false
                 }
               }
      end
    end
  end

  # JSON endpoint for fetching PO details
  def po_details
    @purchase_order = PurchaseOrder.includes(vehicle: :agency).find(params[:id])
    
    render json: {
      id: @purchase_order.id,
      po_number: @purchase_order.po_number,
      vendor: @purchase_order.agency&.name || @purchase_order.vendor,
      amount: @purchase_order.amount,
      vehicle_id: @purchase_order.vehicle_id,
      vehicle: {
        id: @purchase_order.vehicle&.id,
        make: @purchase_order.vehicle&.make,
        model: @purchase_order.vehicle&.model,
        license_plate: @purchase_order.vehicle&.license_plate,
        year: @purchase_order.vehicle&.year_of_manufacture
      }
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Purchase order not found" }, status: :not_found
  end

  private

  def require_billing_officer
    unless current_user.finance? || current_user.admin? || current_user.vmcott_staff?
      redirect_to root_path, alert: "Access denied. Billing Officer access only."
    end
  end

  def set_invoice
    @invoice = Invoice.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to vmcott_billing_invoices_path, alert: "Invoice not found."
  end

  def invoice_params
    params.require(:invoice).permit(
      :vehicle_id, :purchase_order_id, :vendor,
      :invoice_date, :due_date, :amount,
      :notes, :status, :category
    )
  end

  def generate_invoice_number
    date_part = Date.current.strftime('%Y%m%d')
    random_part = SecureRandom.hex(4).upcase
    "VMC-INV-#{date_part}-#{random_part}"
  end

  def generate_payment_reference
    "PAY-#{Date.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
  end
end