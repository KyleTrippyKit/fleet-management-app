# app/controllers/vmcott/parts_controller.rb
module Vmcott
  class PartsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_part, only: [:show, :edit, :update, :destroy, :adjust_stock, :stock]
    before_action :require_vmcott, except: [:index, :show, :search, :stock]

    # Skip the problematic callback for edit action
    skip_around_action :set_pos_transaction_current_user, only: [:edit]

    # ============================================================
    # PARTS CATALOG & SEARCH
    # ============================================================
    
    # Main parts catalog view
    def index
      @q = params[:q].to_s.strip
      @category = params[:category].to_s.strip

      scope = Part.includes(:supplier).order(:name)

      # Optional category filter
      if @category.present?
        scope = scope.where(category: @category)
      end

      # Search across name / part_number / category
      if @q.present?
        scope = scope.where(
          "parts.name ILIKE :q OR parts.part_number ILIKE :q OR parts.category ILIKE :q",
          q: "%#{@q}%"
        )
      end

      @parts = scope.page(params[:page]).per(25)
    end

    # JSON endpoint for live part search (used in purchase request form and inspection form)
    def search
      @parts = Part.where("name ILIKE :q OR part_number ILIKE :q", q: "%#{params[:q]}%")
                   .where(is_active: true)
                   .includes(:supplier)  # Eager load supplier for better performance
                   .limit(20)
      
      render json: @parts.map { |p| 
        {
          id: p.id,
          name: p.name,
          part_number: p.part_number,
          current_stock: p.current_stock,
          minimum_stock: p.minimum_stock,
          reorder_point: p.reorder_point,
          unit_of_measure: p.unit_of_measure,
          price: p.price,
          cost_price: p.cost_price,
          sale_price: p.sale_price,
          supplier: p.supplier ? { id: p.supplier.id, name: p.supplier.name } : nil,
          in_stock: p.current_stock > 0,
          stock_status: p.current_stock > 0 ? 'in_stock' : 'out_of_stock',
          stock_status_color: p.stock_status_color,
          display_name: "#{p.name} (#{p.part_number || 'No Part #'})"
        }
      }
    end

    # JSON endpoint to get current stock for a specific part
    def stock
      @part = Part.find(params[:id])
      render json: { 
        id: @part.id,
        name: @part.name,
        part_number: @part.part_number,
        current_stock: @part.current_stock,
        minimum_stock: @part.minimum_stock,
        reorder_point: @part.reorder_point,
        unit_of_measure: @part.unit_of_measure,
        needs_reorder: @part.current_stock <= @part.reorder_point,
        stock_status: @part.stock_status,
        stock_status_color: @part.stock_status_color,
        suggested_quantity: @part.suggested_reorder_quantity,
        supplier: @part.supplier ? { id: @part.supplier.id, name: @part.supplier.name } : nil
      }
    end

    # Show individual part details
    def show
      @part = Part.find(params[:id])
      @recent_transactions = @part.inventory_transactions
                                   .order(created_at: :desc)
                                   .limit(12)
      @pending_requests = PartsRequest.where(part: @part)
                                      .where(status: ['pending', 'quotations_received', 'purchase_order_created'])
                                      .order(created_at: :desc)
                                      .limit(5)
    end

    # New part form
    def new
      @part = Part.new
      @suppliers = Supplier.where(is_active: true).order(:name)
    end

    # Create new part
    def create
      @part = Part.new(part_params)

      if @part.save
        # Create initial inventory transaction
        if @part.current_stock.to_i > 0
          InventoryTransaction.create!(
            inventory_item: @part,
            quantity: @part.current_stock,
            transaction_type: 'initial_stock',
            notes: "Initial stock setup",
            user: current_user,
            agency: current_user.agency
          )
        end
        
        redirect_to vmcott_part_path(@part), notice: "Part created successfully."
      else
        @suppliers = Supplier.where(is_active: true).order(:name)
        render :new, status: :unprocessable_entity
      end
    end

    # Edit part form
    def edit
      @suppliers = Supplier.where(is_active: true).order(:name)
    end

    # Update part
    def update
      old_stock = @part.current_stock
      
      if @part.update(part_params)
        # Log stock change if it was updated directly
        if old_stock != @part.current_stock
          InventoryTransaction.create!(
            inventory_item: @part,
            previous_quantity: old_stock,
            new_quantity: @part.current_stock,
            quantity: @part.current_stock - old_stock,
            transaction_type: 'manual_adjustment',
            notes: "Manual adjustment from #{old_stock} to #{@part.current_stock}",
            user: current_user,
            agency: current_user.agency
          )
        end
        
        redirect_to vmcott_part_path(@part), notice: "Part updated successfully."
      else
        @suppliers = Supplier.where(is_active: true).order(:name)
        render :edit, status: :unprocessable_entity
      end
    end

    # Delete part (soft delete by setting is_active to false)
    def destroy
      if @part.parts_requests.any? || @part.inspection_job_parts.any? || @part.purchase_order_items.any?
        # Part has been used - soft delete
        @part.update(is_active: false)
        redirect_to vmcott_parts_path, notice: "Part has been deactivated (soft delete)."
      else
        # Part hasn't been used - hard delete
        @part.destroy
        redirect_to vmcott_parts_path, notice: "Part deleted permanently."
      end
    end

    # Stock adjustment (keep for backward compatibility)
    def adjust_stock
      quantity   = params[:quantity].to_i
      direction  = params[:direction].to_s
      notes      = params[:notes].to_s

      unless %w[add subtract].include?(direction)
        return redirect_to vmcott_part_path(@part), alert: "Invalid stock direction."
      end

      if quantity <= 0
        return redirect_to vmcott_part_path(@part), alert: "Quantity must be greater than 0."
      end

      # Use the Part model's adjust_stock method if it exists
      if @part.respond_to?(:adjust_stock)
        if @part.adjust_stock(quantity, direction, notes, current_user)
          msg = direction == "add" ? "increased" : "decreased"
          redirect_to vmcott_part_path(@part), notice: "Stock #{msg} successfully."
        else
          redirect_to vmcott_part_path(@part),
                      alert: "Failed to adjust stock: #{@part.errors.full_messages.join(', ')}"
        end
      else
        # Manual adjustment if method doesn't exist
        old_stock = @part.current_stock
        new_stock = direction == 'add' ? old_stock + quantity : old_stock - quantity
        
        if new_stock < 0
          redirect_to vmcott_part_path(@part), alert: "Cannot subtract more than current stock."
          return
        end
        
        @part.update(current_stock: new_stock)
        
        InventoryTransaction.create!(
          inventory_item: @part,
          previous_quantity: old_stock,
          new_quantity: new_stock,
          quantity: direction == 'add' ? quantity : -quantity,
          transaction_type: 'manual_adjustment',
          notes: notes.presence || "Manual #{direction} of #{quantity}",
          user: current_user,
          agency: current_user.agency
        )
        
        msg = direction == "add" ? "increased" : "decreased"
        redirect_to vmcott_part_path(@part), notice: "Stock #{msg} from #{old_stock} to #{new_stock}."
      end
    end

    private

    def set_part
      @part = Part.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to vmcott_parts_path, alert: "Part not found."
    end

    def part_params
      params.require(:part).permit(
        :name, :part_number, :description, :category, :unit_of_measure,
        :cost_price, :price, :sale_price,
        :current_stock, :minimum_stock, :reorder_point,
        :lead_time_days, :location_in_warehouse, 
        :is_consumable, :is_active,
        :supplier_id, :standard_markup_percentage
      )
    end

    def require_vmcott
      return if current_user.agency&.code == "VMCOTT" || current_user.admin? || 
                current_user.vmcott_staff? || current_user.parts_coordinator?
      redirect_to root_path, alert: "Access denied. VMCOTT users only."
    end
  end
end