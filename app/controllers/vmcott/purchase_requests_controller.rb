# app/controllers/vmcott/purchase_requests_controller.rb
module Vmcott
  class PurchaseRequestsController < ApplicationController
    before_action :require_vmcott_user
    before_action :set_purchase_request, except: [:index, :new, :create]
    
    def index
      @purchase_requests = PurchaseRequest.order(created_at: :desc)
      
      if params[:status].present?
        @purchase_requests = @purchase_requests.where(status: params[:status])
      end
      
      if params[:urgency].present?
        @purchase_requests = @purchase_requests.where(urgency: params[:urgency])
      end
    end
    
    def show
      @items = @purchase_request.purchase_request_items.includes(:part)
    end
    
    def new
      @purchase_request = PurchaseRequest.new
      @parts = Part.active.order(:name)
    end
    
    def create
      @purchase_request = PurchaseRequest.new(purchase_request_params)
      @purchase_request.requested_by = current_user
      
      if @purchase_request.save
        # Add items if provided
        if params[:part_ids].present?
          params[:part_ids].each_with_index do |part_id, index|
            quantity = params[:quantities][index].to_i
            if quantity > 0
              @purchase_request.purchase_request_items.create!(
                part_id: part_id,
                quantity_requested: quantity,
                reason: params[:reasons][index]
              )
            end
          end
        end
        
        redirect_to vmcott_purchase_request_path(@purchase_request),
                    notice: 'Purchase request created successfully.'
      else
        @parts = Part.active.order(:name)
        render :new
      end
    end
    
    def edit
      @parts = Part.active.order(:name)
    end
    
    def update
      if @purchase_request.update(purchase_request_params)
        redirect_to vmcott_purchase_request_path(@purchase_request),
                    notice: 'Purchase request updated successfully.'
      else
        @parts = Part.active.order(:name)
        render :edit
      end
    end
    
    def approve
      if @purchase_request.pending?
        @purchase_request.update!(
          status: 'approved',
          approved_by: current_user,
          approved_at: Time.now
        )
        
        # Create purchase order from approved request
        create_purchase_order_from_request
        
        redirect_to vmcott_purchase_request_path(@purchase_request),
                    notice: 'Purchase request approved and PO created.'
      else
        redirect_to vmcott_purchase_request_path(@purchase_request),
                    alert: 'Cannot approve this request.'
      end
    end
    
    def reject
      if @purchase_request.pending?
        @purchase_request.update!(
          status: 'rejected',
          rejected_by: current_user,
          rejected_at: Time.now,
          notes: params[:rejection_reason]
        )
        
        redirect_to vmcott_purchase_request_path(@purchase_request),
                    notice: 'Purchase request rejected.'
      else
        redirect_to vmcott_purchase_request_path(@purchase_request),
                    alert: 'Cannot reject this request.'
      end
    end
    
    def mark_received
      if @purchase_request.ordered? || @purchase_request.approved?
        @purchase_request.update!(status: 'received', received_at: Time.now)
        
        # Update stock levels
        @purchase_request.purchase_request_items.each do |item|
          part = item.part
          part.update!(
            current_stock: part.current_stock + item.quantity_requested,
            last_reorder_date: Date.today
          )
        end
        
        redirect_to vmcott_purchase_request_path(@purchase_request),
                    notice: 'Items marked as received and stock updated.'
      else
        redirect_to vmcott_purchase_request_path(@purchase_request),
                    alert: 'Cannot mark as received.'
      end
    end
    
    private
    
    def require_vmcott_user
      unless current_user.agency&.code == 'VMCOTT'
        redirect_to main_dashboard_path, 
                    alert: 'Access restricted to VMCOTT users only.'
      end
    end
    
    def set_purchase_request
      @purchase_request = PurchaseRequest.find(params[:id])
    end
    
    def purchase_request_params
      params.require(:purchase_request).permit(
        :needed_by_date, :justification, :notes, :urgency
      )
    end
    
    def create_purchase_order_from_request
      # Create a purchase order from the approved request
      po = PurchaseOrder.create!(
        po_number: "PO-#{Time.now.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}",
        vendor: @purchase_request.items.first&.part&.supplier&.name || 'Multiple Suppliers',
        amount: @purchase_request.total_estimated_cost,
        status: 'draft',
        payment_status: 'unpaid',
        created_by: current_user,
        notes: "Created from Purchase Request #{@purchase_request.pr_number}"
      )
      
      # Add items to PO
      @purchase_request.purchase_request_items.each do |item|
        po.purchase_order_items.create!(
          description: "#{item.part.name} - #{item.part.part_number}",
          quantity: item.quantity_requested,
          unit_price: item.part.cost_price || 0,
          total_price: (item.part.cost_price || 0) * item.quantity_requested,
          part_id: item.part_id
        )
      end
      
      # Update request status
      @purchase_request.update!(status: 'ordered')
    end
  end
end