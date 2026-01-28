# app/controllers/inventory_items_controller.rb
class InventoryItemsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_supplier, only: [:new, :create, :search_items]
  before_action :require_vmcott_user
  
  def new
    @part = @supplier.parts.new
    @part.supplier = @supplier
    @categories = Part.distinct.pluck(:category).compact.sort
  end
  
  def create
    @part = @supplier.parts.new(part_params)
    @part.supplier = @supplier
    
    # Generate part number if not provided
    @part.part_number ||= generate_part_number(@supplier)
    
    # Calculate sale price with markup if not provided
    if @part.cost_price.present? && @part.sale_price.blank?
      markup = @part.standard_markup_percentage || 30.0
      @part.sale_price = @part.cost_price * (1 + markup / 100.0)
    end
    
    if @part.save
      # Create vendor part relationship
      VendorPart.create!(
        supplier: @supplier,
        part: @part,
        vendor_part_number: params[:part][:vendor_part_number],
        vendor_cost_price: @part.cost_price,
        is_active: true
      )
      
      # Create initial inventory transaction if stock is added
      if @part.current_stock.to_i > 0
        InventoryTransaction.create!(
          inventory_item: @part,
          transaction_type: 'receipt',
          quantity: @part.current_stock,
          unit_price: @part.cost_price || 0,
          total_price: (@part.cost_price || 0) * @part.current_stock,
          notes: "Initial stock creation",
          user: current_user
        )
      end
      
      redirect_to supplier_path(@supplier), 
                  notice: 'Inventory item was successfully created.'
    else
      @categories = Part.distinct.pluck(:category).compact.sort
      render :new
    end
  end
  
  def search_items
    query = params[:q].to_s.strip.downcase
    
    if query.present?
      @parts = @supplier.parts.where(
        "LOWER(name) LIKE ? OR LOWER(part_number) LIKE ?",
        "%#{query}%", "%#{query}%"
      ).limit(10)
    else
      @parts = @supplier.parts.limit(10)
    end
    
    render json: @parts.map { |p| 
      { 
        id: p.id, 
        name: p.name,
        part_number: p.part_number,
        current_stock: p.current_stock,
        cost_price: p.cost_price,
        sale_price: p.sale_price,
        category: p.category
      }
    }
  end
  
  private
  
  def set_supplier
    @supplier = Supplier.find(params[:supplier_id])
  end
  
  def part_params
    params.require(:part).permit(
      :name, :part_number, :description, :category,
      :cost_price, :sale_price, :current_stock,
      :minimum_stock, :reorder_point, :unit_of_measure,
      :location_in_warehouse, :is_consumable, :standard_markup_percentage
    )
  end
  
  def generate_part_number(supplier)
    prefix = supplier.name[0..2].upcase
    timestamp = Time.now.strftime('%y%m%d')
    random = SecureRandom.hex(2).upcase
    "#{prefix}-#{timestamp}-#{random}"
  end
  
  def require_vmcott_user
    return if current_user.admin?
    
    unless current_user.agency&.code == 'VMCOTT'
      redirect_to root_path, alert: 'Access denied. VMCOTT users only.'
    end
  end
end