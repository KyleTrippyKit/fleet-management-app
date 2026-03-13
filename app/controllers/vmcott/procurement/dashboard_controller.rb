# app/controllers/vmcott/procurement/dashboard_controller.rb
class Vmcott::Procurement::DashboardController < ApplicationController
  # Skip the dashboard caching for this controller - THIS IS THE FIX!
  skip_around_action :cache_dashboard_data, if: :dashboard_controller?
  
  layout 'application'
  before_action :authenticate_user!
  before_action :require_procurement
  
  # Disable all caching for this controller
  before_action :disable_caching

  def index
    # Initialize stats hash
    @stats = {
      parts_to_quote: load_parts_to_quote_count,
      active_rfqs: load_active_rfqs_count,
      quotes_received: load_quotes_received_count,
      pending_forward: load_pending_forward_count
    }

    # Load data for views
    @pending_parts_requests = load_pending_parts_requests
    @active_rfqs = load_active_rfqs
    @quotations_received = load_quotations_received
    
    # Set headers to prevent caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end

  # RFQ Creation
  def new_rfq
    @parts_request = PartsRequest.find(params[:parts_request_id])
    @rfq = VendorRfq.new
    
    # Disable caching for this action
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end

  def create_rfq
    @rfq = VendorRfq.new(rfq_params)
    @rfq.created_by_id = current_user.id
    @rfq.processing_agency_id = current_user.agency_id
    @rfq.status = 'draft'
    @rfq.rfq_number = generate_rfq_number
    
    if @rfq.save
      # Associate parts request with RFQ
      if params[:parts_request_id].present?
        parts_request = PartsRequest.find(params[:parts_request_id])
        parts_request.update(status: 'rfq_sent')  # Changed from rfq_created to match enum
        # Create RFQ item
        @rfq.vendor_rfq_items.create(
          part_id: parts_request.part_id,
          custom_part_name: parts_request.custom_part_name,
          quantity: parts_request.quantity,
          description: parts_request.part&.description
        )
      end
      
      redirect_to vmcott_procurement_dashboard_path, notice: 'RFQ created successfully'
    else
      render :new_rfq
    end
  end

  def send_rfq
    @rfq = VendorRfq.find(params[:id])
    if @rfq.update(status: 'sent', sent_date: Time.current)
      redirect_to vmcott_procurement_dashboard_path, notice: 'RFQ sent to suppliers'
    else
      redirect_to vmcott_procurement_dashboard_path, alert: 'Failed to send RFQ'
    end
  end

  # Quotation Management
  def upload_quotation
    @rfq = VendorRfq.find(params[:rfq_id])
    @quotation = @rfq.vendor_quotations.new
    
    # Disable caching for this action
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end

  def create_quotation
    @rfq = VendorRfq.find(params[:rfq_id])
    @quotation = @rfq.vendor_quotations.new(quotation_params)
    @quotation.status = 'received'
    
    if @quotation.save
      @rfq.update(status: 'quotations_received')
      redirect_to vmcott_procurement_dashboard_path, notice: 'Quotation uploaded successfully'
    else
      render :upload_quotation
    end
  end

  def forward_to_finance
    @rfq = VendorRfq.find(params[:rfq_id])
    if @rfq.update(status: 'finance_review', finance_review_ready: true)
      redirect_to vmcott_procurement_dashboard_path, notice: 'Quotations forwarded to finance'
    else
      redirect_to vmcott_procurement_dashboard_path, alert: 'Failed to forward quotations'
    end
  end

  # Legacy routes
  def send_rfq_to_suppliers
    @rfq = VendorRfq.find(params[:id])
    redirect_to vmcott_procurement_send_rfq_path(@rfq)
  end

  def receive_quotation
    @rfq = VendorRfq.find(params[:id])
    redirect_to vmcott_procurement_upload_quotation_path(@rfq)
  end

  # PO Details
  def po_details
    @purchase_order = PurchaseOrder.find(params[:id])
    
    # Disable caching for this action
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    render partial: 'po_details', locals: { po: @purchase_order }
  end

  private

  def load_parts_to_quote_count
    # REMOVED AGENCY FILTER - Show ALL parts requests that need quotes
    PartsRequest.where(status: ['pending', 'parts_coordinator_notified'])
                .count
  end

  def load_active_rfqs_count
    # REMOVED AGENCY FILTER - Show ALL active RFQs
    VendorRfq.where(status: ['draft', 'sent'])
             .count
  end

  def load_quotes_received_count
    # REMOVED AGENCY FILTER - Show ALL RFQs with quotes received
    VendorRfq.where(status: 'quotations_received')
             .count
  end

  def load_pending_forward_count
    # REMOVED AGENCY FILTER - Show ALL RFQs ready for finance
    VendorRfq.where(status: 'quotations_received')
             .where.not(id: VendorQuotation.where(status: 'accepted').select(:vendor_rfq_id))
             .count
  end

  def load_pending_parts_requests
    # REMOVED AGENCY FILTER - Show ALL parts requests that need quotes
    PartsRequest.where(status: ['pending', 'parts_coordinator_notified'])
                .includes(:part, inspection: [:vehicle])
                .order(created_at: :desc)
                .limit(20) || []
  end

  def load_active_rfqs
    # REMOVED AGENCY FILTER - Show ALL active RFQs
    VendorRfq.where(status: ['draft', 'sent'])
             .includes(:vendor_rfq_items, :vendor_quotations)
             .order(created_at: :desc)
             .limit(10) || []
  end

  def load_quotations_received
    # REMOVED AGENCY FILTER - Show ALL RFQs with quotes
    VendorRfq.where(status: 'quotations_received')
             .includes(:vendor_rfq_items, :vendor_quotations)
             .order(updated_at: :desc)
             .limit(10) || []
  end

  def generate_rfq_number
    "RFQ-#{Time.current.strftime('%Y%m')}-#{SecureRandom.hex(4).upcase}"
  end

  def rfq_params
    params.require(:vendor_rfq).permit(:due_date, :notes)
  end

  def quotation_params
    params.require(:vendor_quotation).permit(:supplier_id, :valid_until, :notes)
  end

  def require_procurement
    unless current_user.procurement? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Procurement access only."
    end
  end
  
  # Add this method to disable caching for all actions
  def disable_caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end
end