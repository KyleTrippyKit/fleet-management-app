# app/controllers/vmcott/billing/dashboard_controller.rb
class Vmcott::Billing::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_billing
  before_action :ensure_can_create_rfq, only: [:new_rfq, :create_rfq]
  before_action :ensure_can_send_rfq, only: [:send_rfq]
  before_action :ensure_can_upload_quotation, only: [:upload_quotation, :create_quotation]

  def index
    # Parts requests needing RFQ creation
    @pending_parts_requests = PartsRequest.where(status: 'billing_notified')
                                          .includes(inspection: :vehicle, part: :supplier)
                                          .order(created_at: :asc)

    # Active RFQs waiting for vendor responses
    @active_rfqs = VendorRfq.where(status: ['draft', 'sent'])
                            .includes(:vendor_rfq_items, :vendor_quotations)
                            .order(created_at: :desc)

    # Quotations received - ready for finance review
    @quotations_received = VendorRfq.joins(:vendor_quotations)
                                    .where(vendor_quotations: { status: 'received' })
                                    .where.not(vendor_quotations: { status: nil })
                                    .distinct
                                    .includes(:vendor_rfq_items, :vendor_quotations)
                                    .order(updated_at: :desc)

    # Parts received (for stock update)
    @parts_received = Inspection.joins(:parts_requests)
                            .where(parts_requests: { status: 'parts_received' })
                            .where(status: 'parts_coordinator_review')
                            .distinct
                            .includes(:vehicle, :inspection_jobs, :parts_requests)
                            .order(updated_at: :desc)

    # KPI counts for dashboard
    @parts_to_quote_count = PartsRequest.where(status: 'billing_notified').count
    @active_rfqs_count = VendorRfq.where(status: ['draft', 'sent']).count
    @quotes_received_count = VendorQuotation.where(status: 'received').count
  end

  def new_rfq
    @parts_request = PartsRequest.find_by(id: params[:parts_request_id])
    
    if @parts_request.nil?
      redirect_to vmcott_billing_dashboard_path, alert: "Parts request not found."
      return
    end
    
    # Check if RFQ already exists
    existing_rfq = find_existing_rfq(@parts_request)
    if existing_rfq
      redirect_to vmcott_vendor_rfq_path(existing_rfq), 
                  notice: "An RFQ already exists for this part. You can add additional suppliers to it."
      return
    end
    
    @vendor_rfq = VendorRfq.new
    @suppliers = Supplier.where(is_active: true).order(:name)
  end

  def create_rfq
    Rails.logger.info "=" * 50
    Rails.logger.info "CREATE RFQ CALLED with params: #{params.inspect}"
    Rails.logger.info "=" * 50
    
    parts_request = PartsRequest.find(params[:parts_request_id])
    
    # ===== ADDED: Validate suppliers are selected =====
    if params[:supplier_ids].blank?
      flash[:alert] = "Please select at least one supplier."
      redirect_to vmcott_billing_new_rfq_path(parts_request_id: parts_request.id) and return
    end
    # ===== END OF VALIDATION =====
    
    # Build parameters safely
    rfq_params = {
      rfq_number: generate_rfq_number,
      processing_agency_id: current_user.agency_id,
      status: 'draft',
      notes: params[:vendor_rfq]&.[](:notes),
      due_date: params[:vendor_rfq]&.[](:due_date),
      created_by_id: current_user.id
    }
    
    Rails.logger.info "RFQ Params: #{rfq_params.inspect}"
    
    rfq = VendorRfq.new(rfq_params)
    
    if rfq.save
      Rails.logger.info "RFQ SAVED: #{rfq.id}"
      
      # Create RFQ item from parts request
      rfq_item_params = {
        quantity: parts_request.quantity,
        description: parts_request.part_name,
        unit_of_measure: parts_request.part&.unit_of_measure || 'each'
      }
      
      # Handle part_id vs custom_part_name
      if parts_request.part_id.present?
        rfq_item_params[:part_id] = parts_request.part_id
        Rails.logger.info "Using catalog part ID: #{parts_request.part_id}"
      end
      
      if parts_request.custom_part_name.present?
        rfq_item_params[:custom_part_name] = parts_request.custom_part_name
        Rails.logger.info "Using custom part name: #{parts_request.custom_part_name}"
      end
      
      rfq_item = rfq.vendor_rfq_items.create!(rfq_item_params)
      Rails.logger.info "RFQ ITEM CREATED: #{rfq_item.id}"
      
      # Add selected suppliers (now guaranteed to exist)
      supplier_count = 0
      params[:supplier_ids].each do |supplier_id|
        next if supplier_id.blank?
        quotation = rfq.vendor_quotations.create(
          supplier_id: supplier_id,
          status: 'draft'
        )
        supplier_count += 1 if quotation.persisted?
      end
      Rails.logger.info "Created #{supplier_count} supplier quotations"
      
      parts_request.update(status: 'rfq_sent', notified_billing_at: Time.current)
      Rails.logger.info "PartsRequest ##{parts_request.id} updated to rfq_sent"
      
      redirect_to vmcott_vendor_rfq_path(rfq), notice: "RFQ created successfully with #{supplier_count} suppliers. Next: Review and send to suppliers."
    else
      Rails.logger.error "RFQ ERRORS: #{rfq.errors.full_messages}"
      @parts_request = parts_request
      @suppliers = Supplier.where(is_active: true).order(:name)
      @vendor_rfq = rfq
      flash.now[:alert] = "Failed to create RFQ: #{rfq.errors.full_messages.join(', ')}"
      render :new_rfq
    end
  rescue => e
    Rails.logger.error "EXCEPTION in create_rfq: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    redirect_to vmcott_billing_dashboard_path, alert: "Error: #{e.message}"
  end

  def send_rfq
    rfq = VendorRfq.find(params[:id])
    
    if rfq.vendor_quotations.empty?
      redirect_to vmcott_vendor_rfq_path(rfq), alert: "Cannot send RFQ: No suppliers selected."
      return
    end
    
    if rfq.update(status: 'sent', sent_date: Time.current)
      # In a real app, you'd send emails here
      redirect_to vmcott_vendor_rfq_path(rfq), notice: "RFQ sent to #{rfq.vendor_quotations.count} suppliers."
    else
      redirect_to vmcott_vendor_rfq_path(rfq), alert: "Failed to send RFQ."
    end
  end

  def upload_quotation
    @rfq = VendorRfq.find(params[:rfq_id])
    @suppliers = @rfq.vendor_quotations.map(&:supplier)
    @parts = @rfq.vendor_rfq_items.map do |item|
      {
        id: item.id,
        part_id: item.part_id,
        name: item.part_name,
        quantity: item.quantity,
        is_custom: item.custom?
      }
    end
  end

  def create_quotation
    @rfq = VendorRfq.find(params[:rfq_id])
    
    Rails.logger.info "=" * 50
    Rails.logger.info "CREATE QUOTATION STARTED for RFQ ##{@rfq.id}"
    Rails.logger.info "Params: #{params.inspect}"
    Rails.logger.info "=" * 50
    
    quotation = @rfq.vendor_quotations.build(quotation_params)
    
    # Set status
    quotation.status = 'received'
    quotation.assign_attributes(status: 'received')
    Rails.logger.info "Status set to: #{quotation.status}"
    
    if quotation.status.blank? || !VendorQuotation::STATUSES.include?(quotation.status)
      Rails.logger.warn "Status was #{quotation.status.inspect}, forcing to 'received'"
      quotation.write_attribute(:status, 'received')
    end
    
    Rails.logger.info "Final status: #{quotation.status}"
    
    unless quotation.valid?
      Rails.logger.error "Quotation validation errors: #{quotation.errors.full_messages}"
    end
    
    ActiveRecord::Base.transaction do
      if quotation.save
        Rails.logger.info "Quotation saved successfully! ID: #{quotation.id}"
        
        if params[:items].present?
          params[:items].each do |index, item_data|
            next if item_data[:unit_price].blank? || item_data[:unit_price].to_f <= 0
            
            line_item_params = {
              quantity: item_data[:quantity] || 1,
              unit_price: item_data[:unit_price],
              total_price: item_data[:unit_price].to_f * (item_data[:quantity] || 1).to_i,
              description: item_data[:description].presence || item_data[:part_name]
            }
            
            if item_data[:part_id].present? && item_data[:part_id] != 'null' && item_data[:part_id] != ''
              line_item_params[:part_id] = item_data[:part_id]
            end
            
            line_item = quotation.vendor_quotation_lines.create!(line_item_params)
            Rails.logger.info "Line item created: #{line_item.id} (part_id: #{line_item.part_id || 'custom'})"
          end
        end
        
        if params[:attachment].present?
          quotation.attachment.attach(params[:attachment])
          Rails.logger.info "Attachment uploaded"
        end
        
        if @rfq.status == 'sent'
          @rfq.update!(status: 'quotations_received')
          Rails.logger.info "RFQ status updated to quotations_received"
        end
        
        @rfq.vendor_rfq_items.each do |item|
          if item.part_id.present?
            PartsRequest.where(part_id: item.part_id)
                       .where(status: 'rfq_sent')
                       .update_all(status: 'quotations_received')
          end
        end
        
        redirect_to vmcott_vendor_rfq_path(@rfq), 
                    notice: "Quotation from #{quotation.supplier&.name} uploaded successfully."
      else
        Rails.logger.error "Quotation save failed: #{quotation.errors.full_messages}"
        @suppliers = @rfq.vendor_quotations.map(&:supplier)
        flash.now[:alert] = "Failed to upload quotation: #{quotation.errors.full_messages.join(', ')}"
        render :upload_quotation, status: :unprocessable_entity
      end
    end
  rescue => e
    Rails.logger.error "Error in create_quotation: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    @suppliers = @rfq.vendor_quotations.map(&:supplier)
    flash.now[:alert] = "Error uploading quotation: #{e.message}"
    render :upload_quotation, status: :unprocessable_entity
  end

  def forward_to_finance
    rfq = VendorRfq.find(params[:rfq_id])
    
    if rfq.vendor_quotations.where(status: 'received').empty?
      redirect_to vmcott_billing_dashboard_path, alert: "Cannot forward: No quotations have been received yet."
      return
    end
    
    if rfq.update(finance_review_ready: true)
      rfq.vendor_rfq_items.each do |item|
        if item.part_id.present?
          PartsRequest.where(part_id: item.part_id)
                     .where(status: 'quotations_received')
                     .update_all(status: 'finance_review')
        end
      end
      
      if defined?(Notification)
        User.where(role: ['finance', 'admin']).each do |finance_user|
          Notification.create(
            user: finance_user,
            title: "Quotations Ready for Review",
            message: "RFQ ##{rfq.rfq_number} has received #{rfq.vendor_quotations.where(status: 'received').count} quotations.",
            notifiable: rfq,
            link: vmcott_finance_compare_quotations_path(rfq_id: rfq.id)
          )
        end
      end
      
      redirect_to vmcott_billing_dashboard_path, notice: "Quotations forwarded to finance team."
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

  def ensure_can_create_rfq
    parts_request = PartsRequest.find_by(id: params[:parts_request_id])
    return unless parts_request
    
    unless parts_request.status == 'billing_notified'
      redirect_to vmcott_billing_dashboard_path, 
                  alert: "This parts request is not ready for RFQ creation."
      return false
    end
  end

  def ensure_can_send_rfq
    rfq = VendorRfq.find_by(id: params[:id])
    return unless rfq
    
    unless rfq.status == 'draft'
      redirect_to vmcott_billing_dashboard_path, 
                  alert: "This RFQ cannot be sent at this stage."
      return false
    end
  end

  def ensure_can_upload_quotation
    rfq = VendorRfq.find_by(id: params[:rfq_id])
    return unless rfq
    
    unless rfq.status.in?(['sent', 'draft'])
      redirect_to vmcott_billing_dashboard_path, 
                  alert: "Cannot upload quotations for this RFQ at this stage."
      return false
    end
  end

  def quotation_params
    params.require(:vendor_quotation).permit(
      :supplier_id, :notes
    )
  end

  def generate_rfq_number
    "RFQ-#{Date.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
  end
  
  def find_existing_rfq(parts_request)
    if parts_request.part_id.present?
      VendorRfq.joins(:vendor_rfq_items)
               .where(vendor_rfq_items: { part_id: parts_request.part_id })
               .where(status: ['draft', 'sent'])
               .first
    elsif parts_request.custom_part_name.present?
      VendorRfq.joins(:vendor_rfq_items)
               .where(vendor_rfq_items: { custom_part_name: parts_request.custom_part_name })
               .where(status: ['draft', 'sent'])
               .first
    else
      nil
    end
  end
end