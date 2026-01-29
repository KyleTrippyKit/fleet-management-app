# app/controllers/vmcott/purchase_requests_controller.rb
module Vmcott
  class PurchaseRequestsController < ApplicationController
    # Tell Rails to look for templates in the inventory directory
    prepend_view_path "app/views/vmcott/inventory"
    
    before_action :require_vmcott_user
    before_action :set_purchase_request, except: [:index, :new, :create]
    
    def index
      # Redirect to the inventory purchase requests page which already has a template
      redirect_to vmcott_inventory_purchase_requests_path
    end
    
    def show
      @items = @purchase_request.purchase_request_items.includes(:part)
      # You'll need to create app/views/vmcott/purchase_requests/show.html.erb
      # Or redirect to another page
      # For now, render a simple show page
      render 'show'
    end
    
    def new
      @purchase_request = PurchaseRequest.new
      @parts = Part.active.order(:name)
      
      # If creating from a specific part
      if params[:part_id].present?
        @part = Part.find(params[:part_id])
        @purchase_request.part = @part
        @purchase_request.quantity = @part.suggested_reorder_quantity
        @purchase_request.urgency = @part.current_stock <= @part.minimum_stock ? 'high' : 'normal'
        @purchase_request.notes = "Purchase request for #{@part.name}"
        @purchase_request.needed_by_date = Date.today + 7.days
      end
      
      # Render new purchase request form
      render 'new'
    end
    
    def create
      @purchase_request = PurchaseRequest.new(purchase_request_params)
      @purchase_request.requested_by = current_user
      @purchase_request.status = 'pending'
      
      if @purchase_request.save
        redirect_to vmcott_purchase_request_path(@purchase_request),
                    notice: 'Purchase request created successfully.'
      else
        @parts = Part.active.order(:name)
        render 'new'
      end
    end
    
    def edit
      @parts = Part.active.order(:name)
      render 'edit'
    end
    
    def update
      if @purchase_request.update(purchase_request_params)
        redirect_to vmcott_purchase_request_path(@purchase_request),
                    notice: 'Purchase request updated successfully.'
      else
        @parts = Part.active.order(:name)
        render 'edit'
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
    
    def mark_ordered
      if @purchase_request.approved?
        @purchase_request.update!(status: 'ordered', ordered_at: Time.now)
        
        redirect_to vmcott_purchase_request_path(@purchase_request),
                    notice: 'Purchase request marked as ordered.'
      else
        redirect_to vmcott_purchase_request_path(@purchase_request),
                    alert: 'Only approved requests can be marked as ordered.'
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
      return if current_user.admin?
      
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
        :part_id, 
        :quantity, 
        :urgency, 
        :notes, 
        :needed_by_date, 
        :justification
      )
    end
    
    def create_purchase_order_from_request
      # Create a purchase order from the approved request
      po = PurchaseOrder.create!(
        po_number: "PO-#{Time.now.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}",
        vendor: @purchase_request.part&.supplier&.name || 'Multiple Suppliers',
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