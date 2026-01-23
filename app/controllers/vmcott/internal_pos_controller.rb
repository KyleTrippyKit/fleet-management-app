# app/controllers/vmcott/internal_pos_controller.rb
module Vmcott
  class InternalPosController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_vmcott
    
    def index
      @internal_pos_list = fetch_internal_pos_list
      @stats = {
        active: @internal_pos_list.where(status: 'in_progress').count,
        completed_today: @internal_pos_list.where(status: 'completed')
                                           .where('DATE(completed_at) = ?', Date.today).count,
        pending: @internal_pos_list.where(status: 'pending').count
      }
    end
    
    # GET /vmcott/internal_pos/from_po/:purchase_order_id
    def from_po
      @purchase_order = PurchaseOrder.find(params[:purchase_order_id])
      @vehicle = @purchase_order.vehicle
      @quotation = @purchase_order.quotation
      
      # Check if POS already exists for this PO
      @existing_pos = InternalPos.find_by(purchase_order_id: @purchase_order.id)
      
      @internal_pos = InternalPos.new(
        purchase_order: @purchase_order,
        vehicle: @vehicle,
        work_order_number: generate_work_order_number,
        status: 'pending',
        estimated_completion_date: Date.today + 3.days
      )
      
      render :from_po
    end
    
    # POST /vmcott/internal_pos
    def create
      @internal_pos = InternalPos.new(internal_pos_params)
      @internal_pos.created_by = current_user
      
      if @internal_pos.save
        # Update PO status if needed
        if @internal_pos.purchase_order
          @internal_pos.purchase_order.update(status: 'in_progress')
        end
        
        redirect_to vmcott_internal_pos_index_path, 
                    notice: 'Internal POS created successfully.'
      else
        if params[:internal_pos][:purchase_order_id].present?
          @purchase_order = PurchaseOrder.find(params[:internal_pos][:purchase_order_id])
          render :from_po
        else
          render :index
        end
      end
    end
    
    # GET /vmcott/internal_pos/active_work
    def active_work
      @internal_pos_list = InternalPos.where(status: ['pending', 'in_progress'])
                                      .order(priority: :desc, estimated_completion_date: :asc)
                                      .includes(:vehicle, :purchase_order, :assigned_to)
                                      .page(params[:page])
      
      render :active_work
    end
    
    # POST /vmcott/internal_pos/:id/mark_in_progress
    def mark_in_progress
      @internal_pos = InternalPos.find(params[:id])
      if @internal_pos.update(status: 'in_progress', started_at: Time.current)
        redirect_back fallback_location: vmcott_internal_pos_index_path,
                      notice: 'Work marked as in progress.'
      else
        redirect_back fallback_location: vmcott_internal_pos_index_path,
                      alert: 'Failed to update status.'
      end
    end
    
    # POST /vmcott/internal_pos/:id/mark_completed
    def mark_completed
      @internal_pos = InternalPos.find(params[:id])
      if @internal_pos.update(status: 'completed', completed_at: Time.current)
        redirect_back fallback_location: vmcott_internal_pos_index_path,
                      notice: 'Work marked as completed.'
      else
        redirect_back fallback_location: vmcott_internal_pos_index_path,
                      alert: 'Failed to update status.'
      end
    end
    
    # POST /vmcott/internal_pos/:id/create_invoice
    def create_invoice
      @internal_pos = InternalPos.find(params[:id])
      
      # Create invoice from completed work
      @invoice = Invoice.create_from_internal_pos(@internal_pos, current_user)
      
      if @invoice.persisted?
        redirect_to invoice_path(@invoice), 
                    notice: 'Invoice created from completed work.'
      else
        redirect_back fallback_location: vmcott_internal_pos_index_path,
                      alert: "Failed to create invoice: #{@invoice.errors.full_messages.join(', ')}"
      end
    end
    
    private
    
    def ensure_vmcott
      return if current_user.agency&.code == 'VMCOTT'
      redirect_to root_path, alert: 'Access denied - VMCOTT only'
    end
    
    def fetch_internal_pos_list
      InternalPos.where(created_by_id: current_user.id)
                 .or(InternalPos.where(assigned_to_id: current_user.id))
                 .order(created_at: :desc)
                 .includes(:vehicle, :purchase_order, :assigned_to, :created_by)
    end
    
    def generate_work_order_number
      "POS-#{Time.now.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
    end
    
    def internal_pos_params
      params.require(:internal_pos).permit(
        :purchase_order_id, :vehicle_id, :work_order_number, 
        :assigned_to_id, :priority, :estimated_completion_date,
        :notes, :status
      )
    end
  end
end