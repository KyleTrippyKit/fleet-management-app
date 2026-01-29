# app/controllers/vmcott/internal_pos_controller.rb
module Vmcott
  class InternalPosController < ApplicationController
    before_action :authenticate_user!
    before_action :require_vmcott_user
    before_action :set_stats, only: [:index, :active_work, :completed_today]
    
    def index
      @internal_pos = fetch_internal_pos_list.page(params[:page])
    end
    
    def show
      @internal_pos = InternalPos.find(params[:id])
    end
    
    def new
      @internal_pos = InternalPos.new
      
      # If we're creating from a purchase order
      if params[:purchase_order_id].present? && params[:purchase_order_id] != 'new'
        @purchase_order = PurchaseOrder.find_by(id: params[:purchase_order_id])
        if @purchase_order
          @internal_pos.purchase_order = @purchase_order
          @internal_pos.vehicle = @purchase_order.vehicle
          @internal_pos.work_order_number = generate_work_order_number
          @internal_pos.notes = "Created from PO #{@purchase_order.po_number}"
          @internal_pos.status = 'pending'
          @internal_pos.priority = 'normal'
          @internal_pos.estimated_completion_date = Date.today + 3.days
        end
      end
      
      # If we're creating from a part
      if params[:part_id].present?
        @part = Part.find_by(id: params[:part_id])
        if @part
          @internal_pos.notes = "Created for part: #{@part.name} (#{@part.part_number})"
        end
      end
    end
    
    # NEW METHOD: Create internal POS from part - FIXED
    # Fix for line 142 in internal_pos_controller.rb
    def new_from_part
      @part = Part.find(params[:part_id])
      @internal_pos = InternalPos.new(
        work_order_number: generate_work_order_number,
        notes: "Created for part: #{@part.name} (#{@part.part_number})",
        status: 'pending',
        priority: 'normal',
        estimated_completion_date: Date.today + 3.days
      )
      render :new
    end
    
    def create
      @internal_pos = InternalPos.new(internal_pos_params)
      @internal_pos.created_by = current_user
      
      # Handle part reference if provided
      if params[:part_id].present?
        @part = Part.find_by(id: params[:part_id])
        if @part
          @internal_pos.notes ||= ''
          @internal_pos.notes += "\nPart: #{@part.name} (#{@part.part_number})"
        end
      end
      
      if @internal_pos.save
        # Update PO status if needed
        if @internal_pos.purchase_order
          @internal_pos.purchase_order.update(status: 'in_progress')
        end
        
        redirect_to @internal_pos, notice: 'Internal POS created successfully.'
      else
        # Handle render based on source
        if params[:internal_pos][:purchase_order_id].present?
          @purchase_order = PurchaseOrder.find_by(id: params[:internal_pos][:purchase_order_id])
          render :new
        elsif params[:part_id].present?
          @part = Part.find(params[:part_id])
          render :new
        else
          render :new
        end
      end
    end
    
    def edit
      @internal_pos = InternalPos.find(params[:id])
    end
    
    def update
      @internal_pos = InternalPos.find(params[:id])
      
      if @internal_pos.update(internal_pos_params)
        redirect_to @internal_pos, notice: 'Internal POS updated successfully.'
      else
        render :edit
      end
    end
    
    # Fixed from_po method
    def from_po
      # Check if we're creating a new one or using existing
      if params[:purchase_order_id] == 'new'
        # Redirect to new POS form without PO
        redirect_to new_vmcott_internal_pos_path
        return
      end
      
      # Try to find the purchase order
      @purchase_order = PurchaseOrder.find_by(id: params[:purchase_order_id])
      
      if @purchase_order.nil?
        flash[:alert] = "Purchase order not found. Creating new POS without PO reference."
        redirect_to new_vmcott_internal_pos_path
        return
      end
      
      # Check if POS already exists for this PO
      @existing_pos = InternalPos.find_by(purchase_order_id: @purchase_order.id)
      
      if @existing_pos
        redirect_to @existing_pos, notice: 'A POS already exists for this purchase order.'
        return
      end
      
      # Create new internal POS from purchase order
      @internal_pos = InternalPos.new(
        purchase_order: @purchase_order,
        vehicle: @purchase_order.vehicle,
        work_order_number: generate_work_order_number,
        notes: "Created from PO #{@purchase_order.po_number}",
        status: 'pending',
        priority: 'normal',
        estimated_completion_date: Date.today + 3.days
      )
      
      render :new
    end
    
    def mark_in_progress
      @internal_pos = InternalPos.find(params[:id])
      if @internal_pos.update(status: 'in_progress', started_at: Time.current)
        redirect_to @internal_pos, notice: 'POS marked as in progress.'
      else
        redirect_back fallback_location: vmcott_internal_pos_path,
                      alert: 'Failed to update status.'
      end
    end
    
    def mark_completed
      @internal_pos = InternalPos.find(params[:id])
      if @internal_pos.update(status: 'completed', completed_at: Time.current)
        redirect_to @internal_pos, notice: 'POS marked as completed.'
      else
        redirect_back fallback_location: vmcott_internal_pos_path,
                      alert: 'Failed to update status.'
      end
    end
    
    def active_work
      @internal_pos = InternalPos.where(status: ['pending', 'in_progress'])
                                .order(priority: :desc, estimated_completion_date: :asc)
                                .includes(:vehicle, :purchase_order, :assigned_to, :created_by)
                                .page(params[:page])
      render :index
    end

    def completed_today
      @internal_pos = InternalPos.where(status: 'completed')
                                .where('DATE(completed_at) = ?', Date.today)
                                .order(completed_at: :desc)
                                .includes(:vehicle, :purchase_order, :assigned_to, :created_by)
                                .page(params[:page])
      render :index
    end
    
    def create_invoice
      @internal_pos = InternalPos.find(params[:id])
      
      # Check if POS is completed
      unless @internal_pos.completed?
        redirect_to @internal_pos, 
                    alert: 'Cannot create invoice from uncompleted work.'
        return
      end
      
      # Create invoice from completed work
      @invoice = Invoice.create_from_internal_pos(@internal_pos, current_user)
      
      if @invoice.persisted?
        redirect_to invoice_path(@invoice), 
                    notice: 'Invoice created from completed work.'
      else
        redirect_back fallback_location: vmcott_internal_pos_path,
                      alert: "Failed to create invoice: #{@invoice.errors.full_messages.join(', ')}"
      end
    end
    
    # INVENTORY INTEGRATION: Consume parts for this POS
    def consume_parts
      @internal_pos = InternalPos.find(params[:id])
      
      # Get parts to consume from params
      parts_to_consume = params[:parts] || []
      
      begin
        parts_to_consume.each do |part_info|
          part_id = part_info[:id]
          quantity = part_info[:quantity].to_i
          
          if quantity > 0
            part = Part.find(part_id)
            # Create inventory transaction for part consumption
            InventoryTransaction.create!(
              part: part,
              transaction_type: 'consumption',
              quantity: -quantity,
              unit_price: part.cost_price || 0,
              notes: "Consumed for Internal POS #{@internal_pos.work_order_number}",
              created_by: current_user
            )
            
            # Update part stock
            part.update!(current_stock: part.current_stock - quantity)
          end
        end
        
        flash[:success] = "Parts consumed successfully for POS #{@internal_pos.work_order_number}"
      rescue => e
        flash[:alert] = "Failed to consume parts: #{e.message}"
      end
      
      redirect_to @internal_pos
    end
    
    private
    
    def set_stats
      @stats = {
        active: InternalPos.where(status: 'in_progress').count,
        completed_today: InternalPos.where(status: 'completed')
                                   .where('DATE(completed_at) = ?', Date.today).count,
        pending: InternalPos.where(status: 'pending').count
      }
    end
    
    def require_vmcott_user
      return if current_user.admin?
      
      unless current_user.agency&.code == 'VMCOTT'
        redirect_to root_path, alert: 'Access denied. VMCOTT users only.'
      end
    end
    
    def fetch_internal_pos_list
      # Show all POS for admins, otherwise filter by user
      if current_user.admin?
        InternalPos.all
      else
        InternalPos.where(created_by_id: current_user.id)
                   .or(InternalPos.where(assigned_to_id: current_user.id))
      end.order(created_at: :desc)
        .includes(:vehicle, :purchase_order, :assigned_to, :created_by)
    end
    
    def generate_work_order_number
      "POS-#{Time.now.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
    end
    
    def internal_pos_params
      params.require(:internal_pos).permit(
        :work_order_number,
        :purchase_order_id,
        :vehicle_id,
        :assigned_to_id,
        :status,
        :priority,
        :description,
        :notes,
        :estimated_completion_date
      )
    end
  end
end