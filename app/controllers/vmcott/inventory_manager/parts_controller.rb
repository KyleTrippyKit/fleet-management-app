class Vmcott::InventoryManager::PartsController < ApplicationController
  layout 'application'
  before_action :authenticate_user!
  before_action :require_inventory_manager

  def index
    @parts = Part.all
                 .order(:name)
                 .page(params[:page])
                 .per(20)
    render 'vmcott/inventory_manager/parts/index'
  end

  def show
    @part = Part.find(params[:id])
    render 'vmcott/inventory_manager/parts/show'
  end

  def low_stock
    @low_stock_parts = Part.where('current_stock <= reorder_point')
                           .order(current_stock: :asc)
                           .page(params[:page])
                           .per(20)
  
    respond_to do |format|
      format.html { render 'vmcott/inventory/parts/low_stock' }
      format.csv { send_data generate_low_stock_csv(@low_stock_parts), filename: "low_stock_parts_#{Date.current}.csv" }
    end
  end

  def reorder_suggestions
    @parts = []
    
    Part.where('current_stock <= reorder_point * 1.5')
        .each do |part|
      days_of_supply = calculate_days_of_supply(part)
      avg_monthly_consumption = calculate_avg_monthly_consumption(part)
      suggested_qty = [part.reorder_point - part.current_stock, part.minimum_stock].max
      
      @parts << {
        part: part,
        days_of_supply: days_of_supply,
        avg_monthly_consumption: avg_monthly_consumption,
        suggested_quantity: suggested_qty,
        supplier: part.supplier
      }
    end
    
    render 'vmcott/inventory/parts/reorder_suggestions'
  end

  private

  def require_inventory_manager
    unless current_user.inventory_manager? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Inventory Manager access only."
    end
  end
  
  def calculate_days_of_supply(part)
    recent_usage = part.parts_requests.where('created_at > ?', 30.days.ago).sum(:quantity)
    return nil if recent_usage == 0
    
    daily_usage = recent_usage.to_f / 30
    (part.current_stock / daily_usage).round(1)
  end
  
  def calculate_avg_monthly_consumption(part)
    usage = part.parts_requests.where('created_at > ?', 90.days.ago).sum(:quantity)
    (usage / 3).round
  end
  
  def generate_low_stock_csv(parts)
    CSV.generate(headers: true) do |csv|
      csv << ['Part Name', 'Part Number', 'Category', 'Current Stock', 'Minimum Stock', 'Reorder Point', 'Supplier', 'Status']
      parts.each do |part|
        csv << [
          part.name,
          part.part_number,
          part.category,
          part.current_stock,
          part.minimum_stock,
          part.reorder_point,
          part.supplier&.name,
          part.current_stock <= part.minimum_stock ? 'Critical' : 'Low'
        ]
      end
    end
  end
end