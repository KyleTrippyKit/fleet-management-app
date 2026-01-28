# app/controllers/parts_controller.rb
class PartsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_part, only: [:show, :edit, :update, :destroy, :adjust_stock]
  before_action :require_vmcott, except: [:index, :show]

  def index
    @parts = Part.includes(:supplier).all
    @parts = @parts.where(category: params[:category]) if params[:category].present?
    @parts = @parts.where('name ILIKE ?', "%#{params[:search]}%") if params[:search].present?
    @parts = @parts.order(:name).page(params[:page])
    
    @low_stock_parts = Part.below_reorder_point
    @out_of_stock = Part.out_of_stock
  end

  def show
  end

  def new
    @part = Part.new
  end

  def create
    @part = Part.new(part_params)
    
    if @part.save
      redirect_to parts_path, notice: 'Part created successfully.'
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @part.update(part_params)
      redirect_to @part, notice: 'Part updated successfully.'
    else
      render :edit
    end
  end

  def destroy
    @part.destroy
    redirect_to parts_url, notice: 'Part deleted.'
  end

  def adjust_stock
    quantity = params[:quantity].to_i
    direction = params[:direction]
    notes = params[:notes]
    
    if @part.adjust_stock(quantity, direction, notes)
      redirect_to @part, notice: "Stock #{direction == 'add' ? 'increased' : 'decreased'} successfully."
    else
      redirect_to @part, alert: "Failed to adjust stock: #{@part.errors.full_messages.join(', ')}"
    end
  end

  def low_stock
    @parts = Part.below_reorder_point.order(:current_stock)
  end

  def create_purchase_request
    part = Part.find(params[:part_id])
    quantity_needed = part.minimum_stock - part.current_stock
    
    # Create a purchase request (you'll need a PurchaseRequest model)
    # For now, just log it
    Rails.logger.info "Purchase request for #{part.name}: #{quantity_needed} needed"
    
    redirect_to parts_path, notice: "Purchase request created for #{part.name}"
  end

  private

  def set_part
    @part = Part.find(params[:id])
  end

  def part_params
    params.require(:part).permit(
      :name, :part_number, :description, :category, :unit_of_measure,
      :cost_price, :current_stock, :minimum_stock, :reorder_point, 
      :lead_time_days, :location_in_warehouse, :is_consumable, :is_active,
      :supplier_id, :standard_markup_percentage
    )
  end

  def require_vmcott
    return if current_user.agency&.code == 'VMCOTT' || current_user.admin?
    redirect_to root_path, alert: 'Access denied. VMCOTT users only.'
  end
end