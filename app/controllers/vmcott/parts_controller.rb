# app/controllers/vmcott/parts_controller.rb
module Vmcott
  class PartsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_part, only: [:show, :edit, :update, :destroy, :adjust_stock]
    before_action :require_vmcott, except: [:index, :show]

    # Skip the problematic callback for edit action
    skip_around_action :set_pos_transaction_current_user, only: [:edit]

    # ============================================================
    # Option 1: PARTS CATALOG ONLY
    # - Index shows master part data (name, part#, category, supplier, flags)
    # - Stock/low-stock belongs in InventoryController/dashboard
    # ============================================================
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

    def show
      @part = Part.find(params[:id])
  @recent_transactions = @part.inventory_transactions.order(created_at: :desc).limit(12)
    end

    def new
      @part = Part.new
    end

    def create
      @part = Part.new(part_params)

      if @part.save
        redirect_to vmcott_part_path(@part), notice: "Part created successfully."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @part.update(part_params)
        redirect_to vmcott_part_path(@part), notice: "Part updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @part.destroy
      redirect_to vmcott_parts_path, notice: "Part deleted."
    end

    # Optional: keep this action if you still want stock adjustments from part show page.
    # If you want "all stock actions only on Inventory Dashboard", you can remove this.
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

      if @part.adjust_stock(quantity, direction, notes)
        msg = direction == "add" ? "increased" : "decreased"
        redirect_to vmcott_part_path(@part), notice: "Stock #{msg} successfully."
      else
        redirect_to vmcott_part_path(@part),
                    alert: "Failed to adjust stock: #{@part.errors.full_messages.join(', ')}"
      end
    end

    # IMPORTANT:
    # We remove low_stock + create_purchase_request from this controller for Option 1.
    # Those belong to Vmcott::InventoryController (dashboard/low_stock/reorder suggestions).

    private

    def set_part
      @part = Part.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to vmcott_parts_path, alert: "Part not found."
    end

    def part_params
      params.require(:part).permit(
        :name, :part_number, :description, :category, :unit_of_measure,
        :cost_price,
        # Keeping stock fields permitted is okay for forms, but Option 1 means
        # you typically don't edit stock from the Parts catalog screens.
        :current_stock, :minimum_stock, :reorder_point,
        :lead_time_days, :location_in_warehouse, :is_consumable, :is_active,
        :supplier_id, :standard_markup_percentage
      )
    end

    def require_vmcott
      return if current_user.agency&.code == "VMCOTT" || current_user.admin?
      redirect_to root_path, alert: "Access denied. VMCOTT users only."
    end
  end
end
