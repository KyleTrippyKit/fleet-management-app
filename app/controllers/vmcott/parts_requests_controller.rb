# app/controllers/vmcott/parts_requests_controller.rb
module Vmcott
  class PartsRequestsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_parts_request, only: [:show, :update, :update_stock]
    before_action :require_inventory_manager, except: [:index, :show]

    def index
      # Base query with includes - NO AGENCY FILTERING
      @parts_requests = PartsRequest.includes(inspection: [:vehicle], part: [], purchase_order: [])
                                    .order(created_at: :desc)
                                    .page(params[:page])
                                    .per(20)
      
      # Optional: Show agency info for reference but don't filter by it
      @agencies = Agency.all.order(:name) # For display purposes only
      
      # Filter by status if specified
      if params[:status].present?
        @parts_requests = @parts_requests.where(status: params[:status])
      end
      
      # Search by part name or custom part name
      if params[:search].present?
        @parts_requests = @parts_requests
          .left_outer_joins(:part)
          .where("parts.name ILIKE :search OR parts_requests.custom_part_name ILIKE :search", 
                 search: "%#{params[:search]}%")
      end
      
      # Filter by part type (inventory vs custom)
      if params[:type].present?
        case params[:type]
        when 'inventory'
          @parts_requests = @parts_requests.where.not(part_id: nil)
        when 'custom'
          @parts_requests = @parts_requests.where(part_id: nil)
        end
      end
      
      # Get counts for summary stats
      @total_count = @parts_requests.total_count
      @pending_count = @parts_requests.where(status: 'pending').count
      @in_progress_count = @parts_requests.where(status: ['parts_coordinator_notified', 'billing_notified']).count
      @completed_count = @parts_requests.where(status: 'parts_received').count
    end

    def show
      # @parts_request is set by before_action
      # NO AGENCY CHECK - all VMCOTT staff can view all parts requests
      
      # Load associated data safely with nil checks
      @rfqs = safe_load_rfqs
      @purchase_order = safe_load_association(:purchase_order)
      @vendor_invoice = safe_load_association(:vendor_invoice)
      @inspection = safe_load_association(:inspection)
      @vehicle = @inspection&.vehicle if @inspection
      @agency = @vehicle&.agency if @vehicle
      @parts_request_items = safe_load_rfq_items
      
      # No render needed - will render default show.html.erb
    rescue => e
      Rails.logger.error "FATAL ERROR in PartsRequest show action: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      flash[:alert] = "Error loading parts request details: #{e.message}"
      redirect_to vmcott_parts_requests_path and return
    end

    def update
      # Map UI status names to actual enum values
      status_map = {
        'pending' => 'pending',
        'procurement_notified' => 'parts_coordinator_notified',
        'with_coordinator' => 'parts_coordinator_notified',
        'billing_notified' => 'billing_notified',
        'ordered' => 'parts_ordered',
        'parts_received' => 'parts_received',
        'received' => 'parts_received',
        'rejected' => 'rejected'
      }
      
      # NO AGENCY CHECK - all VMCOTT staff can update all parts requests
      
      # Convert the status if needed
      if params[:parts_request].present? && params[:parts_request][:status].present?
        mapped_status = status_map[params[:parts_request][:status]] || params[:parts_request][:status]
        params[:parts_request][:status] = mapped_status
      end
      
      if @parts_request.update(parts_request_params)
        # Update timestamp based on status change
        update_status_timestamps
        
        redirect_to vmcott_parts_request_path(@parts_request), notice: 'Parts request updated successfully.'
      else
        flash.now[:alert] = "Error updating parts request: #{@parts_request.errors.full_messages.join(', ')}"
        render :show, status: :unprocessable_entity
      end
    end

    def update_stock
      # NO AGENCY CHECK - all VMCOTT staff can update stock
      
      if @parts_request.part.present?
        begin
          # Add the parts to inventory
          new_stock = @parts_request.part.current_stock.to_i + @parts_request.quantity
          @parts_request.part.update!(current_stock: new_stock)
          
          # Mark as in stock and update status
          @parts_request.update!(
            in_stock: true,
            status: :parts_received,
            parts_received_at: Time.current
          )
          
          redirect_back fallback_location: vmcott_procurement_dashboard_path, 
                        notice: "Stock updated successfully for #{@parts_request.part.name}. New stock level: #{new_stock}"
        rescue => e
          redirect_back fallback_location: vmcott_procurement_dashboard_path, 
                        alert: "Error updating stock: #{e.message}"
        end
      else
        redirect_back fallback_location: vmcott_procurement_dashboard_path, 
                      alert: "Cannot update stock - this is a custom part with no inventory association"
      end
    end
    
    def create_rfq
      @parts_request = PartsRequest.find(params[:id])
      
      # NO AGENCY CHECK - all VMCOTT staff can create RFQs
      
      begin
        if @parts_request.respond_to?(:create_rfq)
          rfq = @parts_request.create_rfq
          redirect_to vmcott_rfq_path(rfq), notice: 'RFQ created successfully.'
        else
          redirect_to vmcott_parts_request_path(@parts_request), alert: 'RFQ creation method not available for this parts request.'
        end
      rescue => e
        redirect_to vmcott_parts_request_path(@parts_request), alert: "Error creating RFQ: #{e.message}"
      end
    end

    private

    def set_parts_request
      @parts_request = PartsRequest.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      flash[:alert] = "Parts request not found"
      redirect_to vmcott_parts_requests_path
    end

    def parts_request_params
      params.require(:parts_request).permit(:status, :in_stock, :rejection_reason)
    end

    def require_inventory_manager
      unless current_user.inventory_manager? || current_user.admin? || current_user.super_admin?
        redirect_to root_path, alert: 'Access denied. Inventory Manager privileges required.'
      end
    end
    
    # Helper method to safely load associations
    def safe_load_association(association_name)
      @parts_request.send(association_name) if @parts_request.respond_to?(association_name)
    rescue => e
      Rails.logger.error "Error loading #{association_name} for PartsRequest #{@parts_request.id}: #{e.message}"
      nil
    end
    
    # Helper method to safely load RFQs
    def safe_load_rfqs
      if @parts_request.respond_to?(:rfqs)
        @parts_request.rfqs.order(created_at: :desc) 
      else
        []
      end
    rescue => e
      Rails.logger.error "Error loading RFQs for PartsRequest #{@parts_request.id}: #{e.message}"
      []
    end
    
    # Helper method to safely load RFQ items
    def safe_load_rfq_items
      if @parts_request.respond_to?(:vendor_rfq_items)
        @parts_request.vendor_rfq_items
      else
        []
      end
    rescue => e
      Rails.logger.error "Error loading RFQ items for PartsRequest #{@parts_request.id}: #{e.message}"
      []
    end
    
    # Helper method to update timestamps based on status
    def update_status_timestamps
      return unless @parts_request.respond_to?(:update_column)
      
      case @parts_request.status
      when 'parts_coordinator_notified'
        @parts_request.update_column(:notified_parts_coordinator_at, Time.current) if @parts_request.respond_to?(:notified_parts_coordinator_at)
      when 'billing_notified'
        @parts_request.update_column(:notified_billing_at, Time.current) if @parts_request.respond_to?(:notified_billing_at)
      when 'parts_received'
        @parts_request.update_column(:parts_received_at, Time.current) if @parts_request.respond_to?(:parts_received_at)
      end
    rescue => e
      Rails.logger.error "Error updating timestamp: #{e.message}"
      # Continue anyway, timestamp update is not critical
    end
  end
end