# app/controllers/vmcott/billing/dashboard_controller.rb
class Vmcott::Billing::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_billing

  def index
    # Parts that need RFQs (sent from Parts Coordinator with status 'billing_notified')
    @pending_parts_requests = PartsRequest.where(status: 'billing_notified')
                                          .includes(inspection: :vehicle, part: :supplier)
                                          .order(created_at: :asc)

    # Active RFQs waiting for vendor responses (draft or sent)
    @active_rfqs = VendorRfq.where(status: ['draft', 'sent'])
                            .includes(:vendor_rfq_items, :vendor_quotations)
                            .order(created_at: :desc)

    # RFQs that have received quotations (status 'quotations_received')
    @quotations_received = VendorRfq.joins(:vendor_quotations)
                                    .where(vendor_quotations: { status: 'received' })
                                    .distinct
                                    .includes(:vendor_rfq_items, :vendor_quotations)
                                    .order(updated_at: :desc)

    # Parts that have been received and need stock update
    @parts_received = PartsRequest.where(status: 'parts_received')
                                  .where(in_stock: false)
                                  .includes([:inspection, :part, :purchase_order])
                                  .order(parts_received_at: :desc)

    # KPI counts for the dashboard cards
    @parts_to_quote_count = PartsRequest.where(status: 'billing_notified').count
    @active_rfqs_count = VendorRfq.where(status: ['draft', 'sent']).count
    @quotes_received_count = VendorQuotation.where(status: 'received').count
    @pending_parts_requests_count = @pending_parts_requests.count

    # Legacy counts for compatibility
    @pending_rfqs_count = VendorRfq.where(status: 'draft').count
    @quotations_received_count = @quotes_received_count
    @pending_finance_review_count = VendorRfq.where(finance_review_ready: true).count
    @pending_pos_count = PurchaseOrder.where(status: 'pending_approval').count
  end

  def new_rfq
    @parts_request = PartsRequest.find_by(id: params[:parts_request_id])
    
    if @parts_request.nil?
      redirect_to vmcott_billing_dashboard_path, alert: "Parts request not found."
      return
    end
    
    # Check if an RFQ already exists for this parts request
    existing_rfq = find_existing_rfq(@parts_request)
    
    if existing_rfq
      redirect_to vmcott_vendor_rfq_path(existing_rfq), 
                  alert: "An active RFQ already exists for this part. You can add additional suppliers to it."
      return
    end
    
    @vendor_rfq = VendorRfq.new
    @suppliers = Supplier.where(is_active: true)
    
    # Build the RFQ item with proper custom part handling
    build_rfq_item_from_parts_request(@vendor_rfq, @parts_request)
  end

  def create_rfq
    parts_request = PartsRequest.find(params[:parts_request_id])
    
    # Check if an RFQ already exists for this parts request
    existing_rfq = find_existing_rfq(parts_request)
    
    if existing_rfq
      redirect_to vmcott_vendor_rfq_path(existing_rfq), 
                  alert: "An active RFQ already exists for this part. You can add additional suppliers to it."
      return
    end
    
    rfq = VendorRfq.new(
      processing_agency_id: current_user.agency_id,
      status: 'draft',
      notes: params[:vendor_rfq][:notes],
      due_date: params[:vendor_rfq][:due_date],
      rfq_number: generate_rfq_number,
      finance_review_ready: false
    )
    
    if rfq.save
      # Create RFQ item from parts request with custom part support
      create_rfq_item_from_parts_request(rfq, parts_request)
      
      # If multiple suppliers selected, create quotation placeholders
      if params[:supplier_ids].present?
        params[:supplier_ids].each do |supplier_id|
          rfq.vendor_quotations.create(
            supplier_id: supplier_id,
            status: 'pending'
          )
        end
      end
      
      # Update parts request status
      parts_request.update(status: 'rfq_sent', notified_billing_at: Time.current)
      
      redirect_to vmcott_vendor_rfq_path(rfq), notice: "RFQ created successfully. Quotations pending from suppliers."
    else
      redirect_to vmcott_billing_dashboard_path, alert: "Failed to create RFQ: #{rfq.errors.full_messages.join(', ')}"
    end
  end

  def send_rfq
    rfq = VendorRfq.find(params[:id])
    
    if rfq.update(status: 'sent', sent_date: Time.current)
      
      # Notify suppliers (this would be email integration)
      # send_supplier_notifications(rfq)
      
      redirect_to vmcott_vendor_rfq_path(rfq), notice: "RFQ sent to suppliers."
    else
      redirect_to vmcott_vendor_rfq_path(rfq), alert: "Failed to send RFQ."
    end
  end

  def upload_quotation
    @rfq = VendorRfq.find(params[:rfq_id])
    @pending_requests = PartsRequest.where(status: 'rfq_sent')
  end

  def create_quotation
    @rfq = VendorRfq.find(params[:rfq_id])
    
    # Handle multiple quotations from different suppliers
    quotations_created = 0
    
    if params[:quotations].present?
      params[:quotations].each do |quotation_data|
        quotation = @rfq.vendor_quotations.create(
          supplier_id: quotation_data[:supplier_id],
          status: 'received',
          notes: quotation_data[:notes],
          valid_until: quotation_data[:valid_until],
          reference_number: quotation_data[:reference_number]
        )
        
        # Attach the uploaded file if present
        if quotation_data[:attachment].present?
          quotation.attachment.attach(quotation_data[:attachment])
        end
        
        # Create quotation items with prices
        if quotation_data[:items].present?
          quotation_data[:items].each do |item_data|
            quotation.vendor_quotation_lines.create(
              part_id: item_data[:part_id],
              quantity: item_data[:quantity],
              unit_price: item_data[:unit_price],
              total_price: item_data[:unit_price].to_f * item_data[:quantity].to_i,
              description: item_data[:description]
            )
          end
        end
        
        quotations_created += 1
      end
    else
      # Single quotation upload (backward compatibility)
      quotation = @rfq.vendor_quotations.build(quotation_params)
      quotation.status = 'received'
      
      if quotation.save
        # Handle items from the form
        if params[:items].present?
          params[:items].each do |item_data|
            quotation.vendor_quotation_lines.create(
              part_id: item_data[:part_id],
              quantity: item_data[:quantity],
              unit_price: item_data[:unit_price],
              total_price: item_data[:unit_price].to_f * item_data[:quantity].to_i,
              description: item_data[:description]
            )
          end
        end
        
        quotations_created = 1
      end
    end
    
    if quotations_created > 0
      # Update RFQ status
      @rfq.update(status: 'quotations_received')
      
      # Update parts requests status - now using custom_part_name for custom parts
      @rfq.vendor_rfq_items.each do |item|
        if item.part_id.present?
          PartsRequest.where(part_id: item.part_id)
                     .where(status: 'rfq_sent')
                     .update_all(status: 'quotations_received')
        elsif item.custom_part_name.present?
          PartsRequest.where(custom_part_name: item.custom_part_name)
                     .where(status: 'rfq_sent')
                     .update_all(status: 'quotations_received')
        end
      end
      
      redirect_to vmcott_billing_dashboard_path, notice: "#{quotations_created} quotation(s) uploaded successfully."
    else
      redirect_to vmcott_billing_upload_quotation_path(@rfq), alert: "Failed to upload quotations."
    end
  end

  def forward_to_finance
    rfq = VendorRfq.find(params[:rfq_id])
    
    # Check if there are any quotations
    if rfq.vendor_quotations.where(status: 'received').empty?
      redirect_to vmcott_billing_dashboard_path, alert: "Cannot forward: No quotations have been received yet."
      return
    end
    
    # Update RFQ to indicate it's ready for finance review
    if rfq.update(finance_review_ready: true)
      
      # Create notification for finance team
      if defined?(Notification)
        User.where(role: 'finance').each do |finance_user|
          Notification.create(
            user: finance_user,
            title: "Quotations Ready for Review",
            message: "RFQ ##{rfq.rfq_number} has received #{rfq.vendor_quotations.where(status: 'received').count} quotations and is ready for finance review.",
            notifiable: rfq,
            link: vmcott_finance_compare_quotations_path(rfq_id: rfq.id)
          )
        end
      end
      
      redirect_to vmcott_billing_dashboard_path, notice: "Quotations forwarded to finance team for review."
    else
      redirect_to vmcott_billing_dashboard_path, alert: "Failed to forward quotations."
    end
  end

  private

  def require_billing
    unless current_user.billing? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Billing privileges required."
    end
  end

  def rfq_params
    params.require(:vendor_rfq).permit(
      :due_date, :notes,
      vendor_rfq_items_attributes: [:id, :part_id, :custom_part_name, :quantity, :description, :unit_of_measure, :_destroy]
    )
  end

  def quotation_params
    params.require(:vendor_quotation).permit(
      :supplier_id, :total_amount, :valid_until, :notes, :attachment, :reference_number
    )
  end

  def generate_rfq_number
    "RFQ-#{Date.current.strftime('%Y%m')}-#{SecureRandom.hex(4).upcase}"
  end
  
  # Helper method to find existing RFQ for a parts request
  def find_existing_rfq(parts_request)
    if parts_request.part_id.present?
      # Catalog part - search by part_id
      VendorRfq.joins(:vendor_rfq_items)
               .where(vendor_rfq_items: { part_id: parts_request.part_id })
               .where(status: ['draft', 'sent'])
               .first
    elsif parts_request.custom_part_name.present?
      # Custom part - search by custom_part_name (now available!)
      VendorRfq.joins(:vendor_rfq_items)
               .where(vendor_rfq_items: { custom_part_name: parts_request.custom_part_name })
               .where(status: ['draft', 'sent'])
               .first
    else
      nil
    end
  end
  
  # Helper method to build RFQ item from parts request
  def build_rfq_item_from_parts_request(vendor_rfq, parts_request)
    item = vendor_rfq.vendor_rfq_items.build(
      part_id: parts_request.part_id,
      quantity: parts_request.quantity,
      unit_of_measure: parts_request.part&.unit_of_measure || 'each'
    )
    
    if parts_request.part_id.present?
      # Catalog part
      item.description = parts_request.part.name
      item.custom_part_name = nil
    else
      # Custom part - store in dedicated custom_part_name column
      item.custom_part_name = parts_request.custom_part_name
      item.description = parts_request.custom_part_name
    end
  end
  
  # Helper method to create RFQ item from parts request
  def create_rfq_item_from_parts_request(rfq, parts_request)
    item = rfq.vendor_rfq_items.build(
      part_id: parts_request.part_id,
      quantity: parts_request.quantity,
      unit_of_measure: parts_request.part&.unit_of_measure || 'each'
    )
    
    if parts_request.part_id.present?
      # Catalog part
      item.description = parts_request.part.name
      item.custom_part_name = nil
    else
      # Custom part - store in dedicated custom_part_name column
      item.custom_part_name = parts_request.custom_part_name
      item.description = parts_request.custom_part_name
    end
    
    item.save
  end
end