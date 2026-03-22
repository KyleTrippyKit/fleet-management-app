# app/controllers/vmcott/procurement/dashboard_controller.rb

class Vmcott::Procurement::DashboardController < ApplicationController
  # Skip the dashboard caching for this controller
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
    
    # Load RFQs with quotations received OR that have POs
    @all_quotes = load_all_quotes_with_pos
    
    # Load low stock requests count for the button badge
    @low_stock_requests_count = load_low_stock_requests_count
    
    # Set headers to prevent caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end

  # Low Stock Requests page
  def low_stock_requests
    # Get all pending purchase requests (from inventory)
    @low_stock_requests = PurchaseRequest.where(status: 'pending')
                                          .includes(:part, :requested_by)
                                          .order(created_at: :desc)
                                          .to_a || []
    
    # Get part IDs that already have pending requests
    part_ids_with_requests = PurchaseRequest.where(status: 'pending')
                                            .where.not(part_id: nil)
                                            .pluck(:part_id)
                                            .uniq
    
    # Get low stock parts that DON'T have pending requests
    @low_stock_parts_without_requests = Part.where('current_stock <= reorder_point')
                                           .where.not(id: part_ids_with_requests)
                                           .order(current_stock: :asc)
                                           .limit(20)
                                           .to_a || []
    
    # Set headers to prevent caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end

  # RFQ Creation
  def new_rfq
    @parts_request = PartsRequest.find(params[:parts_request_id])
    @rfq = VendorRfq.new
    @suppliers = Supplier.where(is_active: true).order(:name).limit(50)
    
    # Set default values for the RFQ
    @rfq.rfq_number = generate_rfq_number
    @rfq.due_date = 7.days.from_now
    
    # Disable caching for this action
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  rescue ActiveRecord::RecordNotFound
    flash[:alert] = "Parts request not found"
    redirect_to vmcott_procurement_dashboard_path
  end

  def create_rfq
    @rfq = VendorRfq.new(rfq_params)
    @rfq.created_by_id = current_user.id
    @rfq.processing_agency_id = current_user.agency_id
    @rfq.status = 'draft'
    @rfq.rfq_number = generate_rfq_number
    
    # Add vehicle from parts request
    if params[:parts_request_id].present?
      parts_request = PartsRequest.find(params[:parts_request_id])
      @rfq.vehicle_id = parts_request.inspection&.vehicle_id
    end
    
    if @rfq.save
      # Associate parts request with RFQ
      if params[:parts_request_id].present?
        parts_request = PartsRequest.find(params[:parts_request_id])
        parts_request.update(status: 'rfq_sent')
        
        # Create RFQ item
        @rfq.vendor_rfq_items.create(
          part_id: parts_request.part_id,
          custom_part_name: parts_request.custom_part_name,
          quantity: parts_request.quantity,
          description: parts_request.part&.description,
          unit_of_measure: parts_request.part&.unit_of_measure || 'each'
        )
        
        # Handle supplier selections - create vendor quotations for each selected supplier
        if params[:vendor_rfq].present? && params[:vendor_rfq][:supplier_ids].present?
          supplier_ids = params[:vendor_rfq][:supplier_ids]
          # Remove any empty values
          supplier_ids = supplier_ids.reject(&:blank?)
          
          supplier_ids.each do |supplier_id|
            # Create vendor quotation with status 'draft' (matching the model's default)
            @rfq.vendor_quotations.create!(
              supplier_id: supplier_id,
              status: 'draft',
              notes: "RFQ created from parts request ##{parts_request.id}"
            )
          end
          
          # Update the RFQ notes with supplier count
          @rfq.update(notes: "#{@rfq.notes}\nSelected #{supplier_ids.count} suppliers for RFQ.")
          
          Rails.logger.info "Created #{supplier_ids.count} vendor quotations for RFQ #{@rfq.id}"
        else
          Rails.logger.warn "No suppliers selected for RFQ #{@rfq.id}"
        end
      end
      
      # Store the RFQ ID in the session to highlight it on the dashboard
      session[:highlight_rfq_id] = @rfq.id
      
      vehicle_info = @rfq.vehicle ? " Vehicle: #{@rfq.vehicle.license_plate}" : ""
      redirect_to vmcott_procurement_dashboard_path, notice: "RFQ ##{@rfq.rfq_number} created successfully!#{vehicle_info} It has been added to Active RFQs with #{@rfq.vendor_quotations.count} supplier(s)."
    else
      @parts_request = PartsRequest.find(params[:parts_request_id]) if params[:parts_request_id].present?
      @suppliers = Supplier.where(is_active: true).order(:name).limit(50)
      render :new_rfq
    end
  rescue => e
    Rails.logger.error "Error creating RFQ: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    flash[:alert] = "Error creating RFQ: #{e.message}"
    redirect_to vmcott_procurement_dashboard_path
  end

  def send_rfq
    @rfq = VendorRfq.find(params[:id])
    
    # Send email to each supplier
    email_count = 0
    @rfq.vendor_quotations.each do |quotation|
      supplier = quotation.supplier
      if supplier.email.present?
        VendorRfqMailer.send_rfq_to_supplier(@rfq, quotation, supplier).deliver_later
        email_count += 1
      end
    end
    
    # Update RFQ status
    if @rfq.update(status: 'sent', sent_date: Time.current)
      notice = if email_count > 0
        "RFQ ##{@rfq.rfq_number} sent to #{email_count} supplier(s)."
      else
        "RFQ ##{@rfq.rfq_number} marked as sent, but no suppliers had email addresses."
      end
      redirect_to vmcott_procurement_dashboard_path, notice: notice
    else
      redirect_to vmcott_procurement_dashboard_path, alert: 'Failed to send RFQ'
    end
  end

  # Quotation Management
  def upload_quotation
    @rfq = VendorRfq.find(params[:rfq_id])
    @quotation = @rfq.vendor_quotations.new
    @suppliers = Supplier.where(is_active: true).order(:name)
    
    # Get RFQ items to display in the form
    @rfq_items = @rfq.vendor_rfq_items
    
    # Disable caching for this action
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  rescue ActiveRecord::RecordNotFound
    flash[:alert] = "RFQ not found"
    redirect_to vmcott_procurement_dashboard_path
  end

  def create_quotation
    @rfq = VendorRfq.find(params[:rfq_id])
    
    # First, ensure we have RFQ items
    if @rfq.vendor_rfq_items.empty?
      flash[:alert] = "This RFQ has no items. Cannot create quotation."
      redirect_to vmcott_procurement_dashboard_path
      return
    end
    
    Rails.logger.info "RFQ #{@rfq.id} has #{@rfq.vendor_rfq_items.count} items"
    
    # Handle multiple quotations from the form
    if params[:quotations].present?
      success_count = 0
      error_count = 0
      errors = []
      
      # Convert ActionController::Parameters to hash and get values safely
      quotations_hash = params[:quotations].to_unsafe_h
      
      # If it's a hash with numeric keys, get the values
      if quotations_hash.is_a?(Hash)
        quotations_array = quotations_hash.values
      else
        quotations_array = []
      end
      
      Rails.logger.info "Processing #{quotations_array.count} quotations"
      
      quotations_array.each_with_index do |quotation_data, index|
        # Skip if quotation_data is nil or supplier is blank
        next if quotation_data.nil?
        next if quotation_data['supplier_id'].blank?
        
        Rails.logger.info "Processing quotation for supplier #{quotation_data['supplier_id']}"
        Rails.logger.info "Quotation data: #{quotation_data.inspect}"
        
        # Create a new vendor quotation
        @quotation = @rfq.vendor_quotations.new(
          supplier_id: quotation_data['supplier_id'],
          notes: quotation_data['notes'],
          status: 'received'
        )
        
        # Handle file attachment
        if quotation_data['attachment'].present?
          @quotation.attachment = quotation_data['attachment']
        end
        
        # Save the quotation
        if @quotation.save
          Rails.logger.info "Saved quotation #{@quotation.id}"
          
          # Create quotation lines for each RFQ item
          lines_created = 0
          @rfq.vendor_rfq_items.each do |rfq_item|
            # Get unit price from form
            unit_price = nil
            
            # Check in items hash
            if quotation_data['items'].present?
              quotation_data['items'].each do |item_key, item_value|
                if item_key.to_s.include?(rfq_item.id.to_s) && item_value.is_a?(Hash)
                  unit_price = item_value['unit_price']
                  Rails.logger.info "Found unit price #{unit_price} for item #{rfq_item.id} from items hash with key #{item_key}"
                end
              end
            end
            
            # Also check direct unit_price field
            if unit_price.blank? && quotation_data['unit_price'].present?
              unit_price = quotation_data['unit_price']
              Rails.logger.info "Found unit price #{unit_price} from direct field"
            end
            
            if unit_price.blank?
              Rails.logger.warn "No unit price found for RFQ item #{rfq_item.id}"
              next
            end
            
            # Calculate total price
            quantity = rfq_item.quantity.to_f
            unit_price_f = unit_price.to_f
            total_price = (quantity * unit_price_f).round(2)
            
            # Create vendor quotation line
            line = @quotation.vendor_quotation_lines.new(
              part_id: rfq_item.part_id,
              description: rfq_item.description || rfq_item.part&.name || rfq_item.custom_part_name,
              quantity: rfq_item.quantity,
              unit_price: unit_price_f,
              total_price: total_price
            )
            
            if line.save
              lines_created += 1
              Rails.logger.info "Saved quotation line: #{line.quantity}x #{line.description} @ $#{line.unit_price} = $#{line.total_price}"
            else
              Rails.logger.error "Failed to save quotation line: #{line.errors.full_messages}"
            end
          end
          
          if lines_created > 0
            success_count += 1
            Rails.logger.info "Created #{lines_created} lines for quotation #{@quotation.id}"
          else
            Rails.logger.warn "No lines created for quotation #{@quotation.id}"
          end
        else
          error_count += 1
          errors << "Supplier #{quotation_data['supplier_id']}: #{@quotation.errors.full_messages.join(', ')}"
          Rails.logger.error "Failed to save quotation: #{@quotation.errors.full_messages}"
        end
      end
      
      if success_count > 0
        @rfq.update(status: 'quotations_received') if @rfq.status != 'quotations_received'
        
        # Update associated parts requests
        @rfq.vendor_rfq_items.each do |item|
          if item.part_id
            PartsRequest.where(part_id: item.part_id, status: 'rfq_sent')
                       .update_all(status: 'quotations_received')
          end
        end
        
        flash[:notice] = "#{success_count} quotation(s) uploaded successfully"
        flash[:alert] = "#{error_count} quotation(s) failed to upload: #{errors.join('; ')}" if error_count > 0
        redirect_to vmcott_procurement_dashboard_path
      else
        flash[:alert] = "No quotations were uploaded. #{errors.join('; ')}"
        @suppliers = Supplier.where(is_active: true).order(:name)
        @rfq_items = @rfq.vendor_rfq_items
        render :upload_quotation
      end
    else
      # Fallback to single quotation format
      @quotation = @rfq.vendor_quotations.new(quotation_params)
      @quotation.status = 'received'
      
      if @quotation.save
        lines_created = 0
        
        # Create quotation lines from RFQ items
        if @rfq.vendor_rfq_items.present?
          if params[:unit_price].present?
            # Single unit price for all items
            @rfq.vendor_rfq_items.each do |rfq_item|
              unit_price = params[:unit_price].to_f
              total_price = (rfq_item.quantity.to_f * unit_price).round(2)
              
              @quotation.vendor_quotation_lines.create(
                part_id: rfq_item.part_id,
                description: rfq_item.description || rfq_item.part&.name || rfq_item.custom_part_name,
                quantity: rfq_item.quantity,
                unit_price: unit_price,
                total_price: total_price
              )
              lines_created += 1
            end
          elsif params[:quotations] && params[:quotations][0] && params[:quotations][0]['items'].present?
            # Multiple unit prices from form
            params[:quotations][0]['items'].each do |item_key, item_data|
              rfq_item = @rfq.vendor_rfq_items.find { |item| item.id.to_s == item_key.to_s.gsub('item_', '') }
              next unless rfq_item
              
              unit_price = item_data['unit_price'].to_f
              total_price = (rfq_item.quantity.to_f * unit_price).round(2)
              
              @quotation.vendor_quotation_lines.create(
                part_id: rfq_item.part_id,
                description: rfq_item.description || rfq_item.part&.name || rfq_item.custom_part_name,
                quantity: rfq_item.quantity,
                unit_price: unit_price,
                total_price: total_price
              )
              lines_created += 1
            end
          end
        end
        
        if lines_created > 0
          @rfq.update(status: 'quotations_received')
          
          # Update associated parts requests
          @rfq.vendor_rfq_items.each do |item|
            if item.part_id
              PartsRequest.where(part_id: item.part_id, status: 'rfq_sent')
                         .update_all(status: 'quotations_received')
            end
          end
          
          redirect_to vmcott_procurement_dashboard_path, notice: "Quotation uploaded successfully with #{lines_created} item(s)"
        else
          @quotation.destroy
          flash[:alert] = "No unit prices were provided. Please enter unit prices for each part."
          @suppliers = Supplier.where(is_active: true).order(:name)
          @rfq_items = @rfq.vendor_rfq_items
          render :upload_quotation
        end
      else
        flash[:alert] = "Error uploading quotation: #{@quotation.errors.full_messages.join(', ')}"
        @suppliers = Supplier.where(is_active: true).order(:name)
        @rfq_items = @rfq.vendor_rfq_items
        render :upload_quotation
      end
    end
  rescue => e
    Rails.logger.error "Error creating quotation: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    flash[:alert] = "Error uploading quotation: #{e.message}"
    redirect_to vmcott_procurement_dashboard_path
  end

  def forward_to_finance
    @rfq = VendorRfq.find(params[:rfq_id])
    if @rfq.update(status: 'finance_review', finance_review_ready: true)
      # Update associated parts requests
      @rfq.vendor_rfq_items.each do |item|
        if item.part_id
          PartsRequest.where(part_id: item.part_id, status: 'quotations_received')
                     .update_all(status: 'finance_review')
        end
      end
      
      redirect_to vmcott_procurement_dashboard_path, notice: 'Quotations forwarded to finance for review'
    else
      redirect_to vmcott_procurement_dashboard_path, alert: 'Failed to forward quotations'
    end
  rescue => e
    Rails.logger.error "Error forwarding to finance: #{e.message}"
    flash[:alert] = "Error forwarding quotations: #{e.message}"
    redirect_to vmcott_procurement_dashboard_path
  end

  # Legacy routes
  def send_rfq_to_suppliers
    @rfq = VendorRfq.find(params[:id])
    redirect_to vmcott_procurement_send_rfq_path(@rfq)
  end

  def receive_quotation
    @rfq = VendorRfq.find(params[:id])
    redirect_to vmcott_procurement_upload_quotation_path(rfq_id: @rfq.id)
  end

  # PO Details
  def po_details
    @purchase_order = PurchaseOrder.find(params[:id])
    
    # Disable caching for this action
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
    
    render partial: 'po_details', locals: { po: @purchase_order }
  rescue ActiveRecord::RecordNotFound
    render plain: "Purchase order not found", status: :not_found
  end

  private

  def load_low_stock_requests_count
    PurchaseRequest.where(status: 'pending').count
  end

  def load_parts_to_quote_count
    PartsRequest.where(status: ['pending', 'parts_coordinator_notified'])
                .count
  end

  def load_active_rfqs_count
    VendorRfq.where(status: ['draft', 'sent'])
             .count
  end

  def load_quotes_received_count
    VendorRfq.where(status: 'quotations_received')
             .count
  end

  def load_pending_forward_count
    VendorRfq.where(status: 'quotations_received')
             .where.not(id: VendorQuotation.where(status: 'accepted').select(:vendor_rfq_id))
             .count
  end

  def load_pending_parts_requests
    PartsRequest.where(status: ['pending', 'parts_coordinator_notified'])
                .includes(:part, inspection: [:vehicle])
                .order(created_at: :desc)
                .limit(20) || []
  end

  def load_active_rfqs
    VendorRfq.where(status: ['draft', 'sent'])
             .includes(:vendor_rfq_items, :vendor_quotations)
             .order(created_at: :desc)
             .limit(10) || []
  end

  # NEW METHOD: Load all RFQs including those with POs
  def load_all_quotes_with_pos
    # Get RFQs with quotations received OR that have POs
    VendorRfq.where(status: 'quotations_received')
             .or(VendorRfq.where.not(po_sent_at: nil))
             .includes(:vendor_rfq_items, :vendor_quotations, :vehicle)
             .order(created_at: :desc)
             .limit(20) || []
  end

  def generate_rfq_number
    "RFQ-#{Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
  end

  def rfq_params
    params.require(:vendor_rfq).permit(:due_date, :notes)
  end

  def quotation_params
    params.require(:vendor_quotation).permit(:supplier_id, :notes, :attachment)
  end

  def require_procurement
    unless current_user.procurement? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Procurement access only."
    end
  end
  
  def disable_caching
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end
end