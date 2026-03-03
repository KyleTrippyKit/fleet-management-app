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
    @parts_received = PartsRequest.where(status: 'parts_received')
                                  .where(in_stock: false)
                                  .includes(:inspection, :part, :purchase_order)
                                  .order(parts_received_at: :desc)

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
    
    @vendor_rfq = VendorRfq.new
    @suppliers = Supplier.where(is_active: true).order(:name)
  end

  def create_rfq
    parts_request = PartsRequest.find(params[:parts_request_id])
    
    rfq = VendorRfq.new(
      rfq_number: generate_rfq_number,
      processing_agency_id: current_user.agency_id,
      status: 'draft',
      notes: params[:vendor_rfq][:notes],
      due_date: params[:vendor_rfq][:due_date],
      created_by_id: current_user.id
    )
    
    if rfq.save
      # Create RFQ item from parts request
      rfq.vendor_rfq_items.create!(
        part_id: parts_request.part_id,
        custom_part_name: parts_request.custom_part_name,
        quantity: parts_request.quantity,
        description: parts_request.part&.name || parts_request.custom_part_name,
        unit_of_measure: parts_request.part&.unit_of_measure || 'each'
      )
      
      # Add selected suppliers
      if params[:supplier_ids].present?
        params[:supplier_ids].each do |supplier_id|
          rfq.vendor_quotations.create(
            supplier_id: supplier_id,
            status: 'draft'
          )
        end
      end
      
      parts_request.update(status: 'rfq_sent', notified_billing_at: Time.current)
      
      redirect_to vmcott_vendor_rfq_path(rfq), notice: "RFQ created successfully."
    else
      redirect_to vmcott_billing_new_rfq_path(parts_request_id: parts_request.id), 
                  alert: "Failed to create RFQ: #{rfq.errors.full_messages.join(', ')}"
    end
  end

  def send_rfq
    rfq = VendorRfq.find(params[:id])
    
    if rfq.vendor_quotations.empty?
      redirect_to vmcott_vendor_rfq_path(rfq), alert: "Cannot send RFQ: No suppliers selected."
      return
    end
    
    if rfq.update(status: 'sent', sent_date: Time.current)
      # In a real app, you'd send emails here
      flash[:notice] = "RFQ sent to #{rfq.vendor_quotations.count} suppliers."
    else
      flash[:alert] = "Failed to send RFQ."
    end
    
    redirect_to vmcott_vendor_rfq_path(rfq)
  end

  def upload_quotation
    @rfq = VendorRfq.find(params[:rfq_id])
  end

  def create_quotation
    @rfq = VendorRfq.find(params[:rfq_id])
    
    quotation = @rfq.vendor_quotations.build(quotation_params)
    quotation.status = 'received'
    
    if quotation.save
      # Add line items
      if params[:items].present?
        params[:items].each do |item_data|
          quotation.vendor_quotation_lines.create(
            part_id: item_data[:part_id],
            quantity: item_data[:quantity],
            unit_price: item_data[:unit_price],
            total_price: item_data[:unit_price].to_f * item_data[:quantity].to_i,
            description: item_data[:description] || item_data[:part_name]
          )
        end
      end
      
      # Update RFQ status if this is the first quotation
      if @rfq.vendor_quotations.count == 1
        @rfq.update(status: 'quotations_received')
      end
      
      # Update related parts requests
      @rfq.vendor_rfq_items.each do |item|
        if item.part_id.present?
          PartsRequest.where(part_id: item.part_id)
                     .where(status: 'rfq_sent')
                     .update_all(status: 'quotations_received')
        end
      end
      
      redirect_to vmcott_billing_dashboard_path, notice: "Quotation uploaded successfully."
    else
      redirect_to vmcott_billing_upload_quotation_path(@rfq), 
                  alert: "Failed to upload quotation: #{quotation.errors.full_messages.join(', ')}"
    end
  end

  def forward_to_finance
    rfq = VendorRfq.find(params[:rfq_id])
    
    if rfq.vendor_quotations.where(status: 'received').empty?
      redirect_to vmcott_billing_dashboard_path, alert: "Cannot forward: No quotations have been received yet."
      return
    end
    
    if rfq.update(finance_review_ready: true)
      # Update related parts requests
      rfq.vendor_rfq_items.each do |item|
        if item.part_id.present?
          PartsRequest.where(part_id: item.part_id)
                     .where(status: 'rfq_sent')
                     .update_all(status: 'finance_review')
        end
      end
      
      # Notify finance team
      User.where(role: ['finance', 'admin']).each do |finance_user|
        Notification.create(
          user: finance_user,
          title: "Quotations Ready for Review",
          message: "RFQ ##{rfq.rfq_number} has received #{rfq.vendor_quotations.where(status: 'received').count} quotations.",
          notifiable: rfq,
          link: vmcott_finance_compare_quotations_path(rfq_id: rfq.id)
        ) if defined?(Notification)
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
      :supplier_id, :valid_until, :notes, :reference_number
    )
  end

  def generate_rfq_number
    "RFQ-#{Date.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
  end
end