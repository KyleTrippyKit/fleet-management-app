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
      render 'show'
    end
    
    def new
      @purchase_request = PurchaseRequest.new
      @parts = Part.active.order(:name)
      
      # Set default needed_by_date to 7 days from now
      @purchase_request.needed_by_date = 7.days.from_now.to_date
      
      # If creating from a specific part
      if params[:part_id].present?
        @part = Part.find(params[:part_id])
        @purchase_request.part = @part
        @purchase_request.quantity = @part.suggested_reorder_quantity
        @purchase_request.urgency = @part.current_stock <= @part.minimum_stock ? 'high' : 'normal'
        @purchase_request.notes = "Purchase request for #{@part.name}"
      end
      
      render 'new'
    end
    
    def create
      @purchase_request = PurchaseRequest.new(purchase_request_params)
      @purchase_request.requested_by = current_user
      @purchase_request.status = 'pending'
      
      if @purchase_request.save
        # Notify billing team
        User.where(role: 'billing').each do |billing_user|
          Notification.create!(
            user: billing_user,
            title: "New Purchase Request: #{@purchase_request.part&.name}",
            message: "#{current_user.name} requested #{@purchase_request.quantity} units, needed by #{@purchase_request.needed_by_date}",
            notifiable: @purchase_request,
            link: vmcott_billing_dashboard_path
          ) if defined?(Notification)
        end
        
        redirect_to vmcott_purchase_request_path(@purchase_request),
                    notice: 'Purchase request created successfully and sent to billing team.'
      else
        @parts = Part.active.order(:name)
        render 'new', status: :unprocessable_entity
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
        render 'edit', status: :unprocessable_entity
      end
    end
    
    def approve
      if @purchase_request.pending?
        @purchase_request.update!(
          status: 'approved',
          approved_by: current_user,
          approved_at: Time.current
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
          rejected_at: Time.current,
          notes: [@purchase_request.notes, "Rejection reason: #{params[:rejection_reason]}"].compact.join("\n")
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
        @purchase_request.update!(status: 'ordered', ordered_at: Time.current)
        
        redirect_to vmcott_purchase_request_path(@purchase_request),
                    notice: 'Purchase request marked as ordered.'
      else
        redirect_to vmcott_purchase_request_path(@purchase_request),
                    alert: 'Only approved requests can be marked as ordered.'
      end
    end
    
    def mark_received
      if @purchase_request.ordered? || @purchase_request.approved?
        @purchase_request.update!(status: 'received', received_at: Time.current)
        
        # Update stock levels
        @purchase_request.purchase_request_items.each do |item|
          part = item.part
          if part.present?
            part.stock_in(
              item.quantity_requested,
              user: current_user,
              reference: @purchase_request,
              notes: "Received from purchase request ##{@purchase_request.id}"
            )
          end
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
    rescue ActiveRecord::RecordNotFound
      redirect_to vmcott_purchase_requests_path, alert: 'Purchase request not found.'
    end
    
    def purchase_request_params
      params.require(:purchase_request).permit(
        :part_id, 
        :quantity, 
        :urgency, 
        :notes, 
        :needed_by_date,  # ← This is now properly permitted
        :justification
      )
    end
    
    def create_purchase_order_from_request
      # Create a purchase order from the approved request
      return unless @purchase_request.part.present?
      
      po = PurchaseOrder.create!(
        po_number: "PO-#{Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}",
        vendor: @purchase_request.part.supplier&.name || 'Multiple Suppliers',
        amount: @purchase_request.total_estimated_cost,
        status: 'draft',
        payment_status: 'unpaid',
        created_by_id: current_user.id,
        notes: "Created from Purchase Request ##{@purchase_request.id} - Needed by #{@purchase_request.needed_by_date}"
      )
      
      # Add items to PO
      if @purchase_request.purchase_request_items.any?
        @purchase_request.purchase_request_items.each do |item|
          po.purchase_order_items.create!(
            description: "#{item.part.name} - #{item.part.part_number}",
            quantity: item.quantity_requested,
            unit_price: item.part.cost_price || 0,
            total_price: (item.part.cost_price || 0) * item.quantity_requested,
            part_id: item.part_id
          )
        end
      else
        # Single item request
        po.purchase_order_items.create!(
          description: "#{@purchase_request.part.name} - #{@purchase_request.part.part_number}",
          quantity: @purchase_request.quantity,
          unit_price: @purchase_request.part.cost_price || 0,
          total_price: @purchase_request.total_estimated_cost,
          part_id: @purchase_request.part_id
        )
      end
      
      # Update request status
      @purchase_request.update!(status: 'ordered')
      
      po
    end
  end
end