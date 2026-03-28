# app/controllers/stock_levels_controller.rb
class StockLevelsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin_or_finance
  
  def index
    @agency = Agency.find_by(code: 'VMCOTT')
    @parts = Part.joins(:job_templates)
                 .where(job_templates: { agency_id: @agency.id })
                 .distinct
                 .order(:name)
                 .paginate(page: params[:page], per_page: 50)
    
    @categories = Part.pluck(:category).uniq.compact.sort
    @suppliers = Part.pluck(:supplier).uniq.compact.sort
    
    if params[:category].present?
      @parts = @parts.where(category: params[:category])
    end
    
    if params[:supplier].present?
      @parts = @parts.where(supplier: params[:supplier])
    end
    
    if params[:search].present?
      @parts = @parts.where("name ILIKE ? OR part_number ILIKE ?", "%#{params[:search]}%", "%#{params[:search]}%")
    end
  end
  
  def update
    @part = Part.find(params[:id])
    
    if @part.update(part_params)
      # Create audit log
      create_stock_adjustment_log(@part, current_user)
      
      respond_to do |format|
        format.html { redirect_to stock_levels_path, notice: "Stock levels updated for #{@part.name}" }
        format.json { render json: { success: true, part: @part } }
      end
    else
      respond_to do |format|
        format.html { redirect_to stock_levels_path, alert: "Failed to update: #{@part.errors.full_messages.join(', ')}" }
        format.json { render json: { success: false, errors: @part.errors }, status: :unprocessable_entity }
      end
    end
  end
  
  def update_batch
    updates = params[:parts] || {}
    successful_updates = []
    failed_updates = []
    
    updates.each do |part_id, part_data|
      part = Part.find_by(id: part_id)
      next unless part
      
      if part.update(
        current_stock: part_data[:current_stock],
        minimum_stock: part_data[:minimum_stock],
        reorder_point: part_data[:reorder_point]
      )
        create_stock_adjustment_log(part, current_user)
        successful_updates << part.name
      else
        failed_updates << "#{part.name}: #{part.errors.full_messages.join(', ')}"
      end
    end
    
    if failed_updates.empty?
      redirect_to stock_levels_path, notice: "Successfully updated #{successful_updates.count} parts"
    else
      redirect_to stock_levels_path, 
                  alert: "Updated #{successful_updates.count} parts. Failed: #{failed_updates.join('; ')}"
    end
  end
  
  def export
    @parts = Part.joins(:job_templates)
                 .where(job_templates: { agency_id: Agency.find_by(code: 'VMCOTT').id })
                 .distinct
                 .order(:name)
    
    respond_to do |format|
      format.csv do
        headers['Content-Disposition'] = "attachment; filename=\"vmcott-stock-levels-#{Date.today}.csv\""
        headers['Content-Type'] ||= 'text/csv'
      end
    end
  end
  
  def import
    if params[:file].present?
      result = Part.import_stock_levels(params[:file].path, current_user)
      
      if result[:success]
        redirect_to stock_levels_path, notice: "Imported #{result[:count]} parts successfully"
      else
        redirect_to stock_levels_path, alert: "Import failed: #{result[:errors].join(', ')}"
      end
    else
      redirect_to stock_levels_path, alert: "Please select a file to import"
    end
  end
  
  private
  
  def part_params
    params.require(:part).permit(:current_stock, :minimum_stock, :reorder_point)
  end
  
  def require_admin_or_finance
    unless current_user.admin? || current_user.finance? || current_user.vmcott_staff?
      redirect_to root_path, alert: 'Access denied. Admin or Finance staff only.'
    end
  end
  
  def create_stock_adjustment_log(part, user)
    return unless defined?(AuditLog) && AuditLog.table_exists?
    
    AuditLog.create!(
      user_id: user.id,
      record_type: 'Part',
      record_id: part.id,
      action: 'stock_level_adjustment',
      audit_changes: {
        part_name: part.name,
        part_id: part.id,
        old_values: part.previous_changes.transform_values(&:first),
        new_values: {
          current_stock: part.current_stock,
          minimum_stock: part.minimum_stock,
          reorder_point: part.reorder_point
        }
      },
      ip_address: request.remote_ip,
      note: "Stock levels updated for #{part.name}"
    )
  end