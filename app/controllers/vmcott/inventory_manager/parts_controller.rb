# app/controllers/vmcott/inventory_manager/parts_controller.rb
class Vmcott::InventoryManager::PartsController < ApplicationController
  layout 'application'
  before_action :authenticate_user!
  before_action :require_inventory_manager

  def index
    @parts = Part.where(agency_id: current_user.agency_id)
                 .order(:name)
                 .page(params[:page])
                 .per(20)
  end

  def show
    @part = Part.find(params[:id])
  end

  def low_stock
    @parts = Part.where('current_stock <= reorder_point')
                 .where(agency_id: current_user.agency_id)
                 .order(:name)
                 .page(params[:page])
                 .per(20)
    render :index
  end

  def reorder_suggestions
    @parts = Part.where('current_stock <= reorder_point * 1.5')
                 .where(agency_id: current_user.agency_id)
                 .order(:name)
                 .page(params[:page])
                 .per(20)
    render :index
  end

  private

  def require_inventory_manager
    unless current_user.inventory_manager? || current_user.admin?
      redirect_to root_path, alert: "Access denied. Inventory Manager access only."
    end
  end
end